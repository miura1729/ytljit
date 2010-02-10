#include <stdlib.h>
#include <setjmp.h>
#include <dlfcn.h>
#include "ruby.h"

#include "ytljit.h"

VALUE ytljit_mYTLJit;
VALUE ytljit_cCodeSpace;

static void *dl_handles[MAX_DL_HANDLES];
static int used_dl_handles = 0;

VALUE 
ytljit_address_of(VALUE self, VALUE symstr)
{
  int i;
  char *sym;
  void *add;

  sym = StringValuePtr(symstr);
  for (i = 0; i < used_dl_handles; i++) {
    if ((add = dlsym(dl_handles[i], sym)) != NULL) {
      return ULONG2NUM((unsigned long)add);
    }
  }

  return Qnil;
}

VALUE
ytljit_code_space_allocate(VALUE klass)
{
  struct CodeSpace *obj;
 
  obj = malloc(sizeof(struct CodeSpace) + 16);
  obj->size = 16;
  obj->used = 0;
  return Data_Wrap_Struct(klass, NULL, NULL, (void *)obj);
}

VALUE
ytljit_code_space_emit(VALUE self, VALUE offset, VALUE src)
{
  struct CodeSpace *raw_cs;
  char *src_ptr;
  int src_len;
  int raw_offset;
  int cooked_offset;
  struct RData *data_cs;

  raw_cs = (struct CodeSpace *)DATA_PTR(self);
  src_ptr = RSTRING_PTR(src);
  src_len = RSTRING_LEN(src);
  raw_offset = FIX2INT(offset);
  cooked_offset = raw_offset;
  if (raw_offset < 0) {
    cooked_offset = raw_cs->used - raw_offset + 1;
  }

  while (raw_cs->size <= src_len + cooked_offset + 4) {
    int newsize = raw_cs->size * 2;
    
    raw_cs = realloc(raw_cs, newsize);
    raw_cs->size = newsize;
  }
  
  memcpy(raw_cs->body + cooked_offset, src_ptr, src_len);
  if (raw_cs->used < cooked_offset + src_len) {
    raw_cs->used = cooked_offset + src_len;
  }
  data_cs = (struct RData *)self;
  data_cs->data = raw_cs;

  return src;
}

VALUE
ytljit_code_space_ref(VALUE self, VALUE offset)
{
  struct CodeSpace *raw_cs;

  int raw_offset;
  int cooked_offset;

  raw_cs = (struct CodeSpace *)DATA_PTR(self);
  raw_offset = FIX2INT(offset);
  cooked_offset = raw_offset;
  if (raw_offset < 0) {
    cooked_offset = raw_cs->used - raw_offset + 1;
  }

  return INT2FIX(raw_cs->body[cooked_offset]);
}

VALUE
ytljit_code_current_pos(VALUE self)
{
  struct CodeSpace *raw_cs;

  raw_cs = (struct CodeSpace *)DATA_PTR(self);
  return INT2NUM(raw_cs->used);
}

VALUE
ytljit_code_set_current_pos(VALUE self, VALUE val)
{
  struct CodeSpace *raw_cs;

  raw_cs = (struct CodeSpace *)DATA_PTR(self);
  raw_cs->used = NUM2INT(val);
  return val;
}

VALUE
ytljit_code_base_address(VALUE self)
{
  struct CodeSpace *raw_cs;

  raw_cs = (struct CodeSpace *)DATA_PTR(self);
  return UINT2NUM((unsigned long)raw_cs->body);
}

VALUE
ytljit_code_call(VALUE self, VALUE addr)
{
  void *raddr;
  VALUE rc;

  raddr = (void *)NUM2ULONG(addr);

  asm("call *%1 \n\t" 
      "mov %%eax, %0"
      : "=r" (rc) : "r" (raddr) : "%eax", "%ebx");

  return rc;
}
  
VALUE
ytljit_code_space_code(VALUE self)
{
  struct CodeSpace *raw_cs;

  raw_cs = (struct CodeSpace *)DATA_PTR(self);

  return rb_str_new(raw_cs->body, raw_cs->used);
}  

VALUE
ytljit_code_space_to_s(VALUE self)
{
  struct CodeSpace *raw_cs;

  raw_cs = (struct CodeSpace *)DATA_PTR(self);

  return rb_sprintf("#<codeSpace %x base=%x:...>", (unsigned int)self, (unsigned int)raw_cs->body);
}

void
ytljit_step_handler()
{
  jmp_buf jbuf;
  void *pc;
  pc = __builtin_return_address(0);
  if (setjmp(jbuf) != 0) {
    return;
  }
  printf("execute: 0x%x\n", (unsigned int)pc);
  fflush(stdout);
  longjmp(jbuf, 1);
}

void 
Init_ytljit() 
{
  ytljit_mYTLJit = rb_define_module("YTLJit");

  rb_define_module_function(ytljit_mYTLJit, "address_of", ytljit_address_of, 1);

  ytljit_cCodeSpace = rb_define_class_under(ytljit_mYTLJit, "CodeSpace", rb_cObject);
  rb_define_alloc_func(ytljit_cCodeSpace, ytljit_code_space_allocate);
  rb_define_method(ytljit_cCodeSpace, "[]=", ytljit_code_space_emit, 2);
  rb_define_method(ytljit_cCodeSpace, "[]", ytljit_code_space_ref, 1);
  rb_define_method(ytljit_cCodeSpace, "current_pos", ytljit_code_current_pos, 0);
  rb_define_method(ytljit_cCodeSpace, "current_pos=", ytljit_code_set_current_pos, 1);
  rb_define_method(ytljit_cCodeSpace, "base_address", ytljit_code_base_address, 0);
  rb_define_method(ytljit_cCodeSpace, "call", ytljit_code_call, 1);
  rb_define_method(ytljit_cCodeSpace, "code", ytljit_code_space_code, 0);
  rb_define_method(ytljit_cCodeSpace, "to_s", ytljit_code_space_to_s, 0);

  /* Open Handles */
  OPEN_CHECK(dl_handles[used_dl_handles] = dlopen("cygwin1.dll", RTLD_LAZY));
  used_dl_handles++;
  OPEN_CHECK(dl_handles[used_dl_handles] = dlopen("cygruby191.dll", RTLD_LAZY));
  used_dl_handles++;
  OPEN_CHECK(dl_handles[used_dl_handles] = dlopen("ytljit.so", RTLD_LAZY));
  used_dl_handles++;
}

