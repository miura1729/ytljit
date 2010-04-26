#include <stdlib.h>
#include <setjmp.h>
#include <dlfcn.h>
#include "ruby.h"

#include "ytljit.h"

VALUE ytl_mYTLJit;
VALUE ytl_cCodeSpace;
VALUE ytl_cStepHandler;
VALUE ytl_eStepHandler;
static ID ytl_v_step_handler_id;

static void *dl_handles[MAX_DL_HANDLES];
static int used_dl_handles = 0;

VALUE 
ytl_address_of(VALUE self, VALUE symstr)
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
ytl_memref(VALUE self, VALUE addr)
{
  return UINT2NUM(*((char *)NUM2LONG(addr)));
}

VALUE
ytl_code_space_allocate(VALUE klass)
{
  struct CodeSpace *obj;
 
  obj = malloc(sizeof(struct CodeSpace) + 16);
  obj->size = 16;
  obj->used = 0;
  return Data_Wrap_Struct(klass, NULL, NULL, (void *)obj);
}

VALUE
ytl_code_space_emit(VALUE self, VALUE offset, VALUE src)
{
  struct CodeSpace *raw_cs;
  char *src_ptr;
  size_t src_len;
  int raw_offset;
  size_t cooked_offset;
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
    size_t newsize = raw_cs->size * 2;
    
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
ytl_code_space_ref(VALUE self, VALUE offset)
{
  struct CodeSpace *raw_cs;

  int raw_offset;
  size_t cooked_offset;

  raw_cs = (struct CodeSpace *)DATA_PTR(self);
  raw_offset = FIX2INT(offset);
  cooked_offset = raw_offset;
  if (raw_offset < 0) {
    size_t rev_offset = -raw_offset;
    cooked_offset = raw_cs->used + rev_offset + 1;
  }

  return INT2FIX(raw_cs->body[cooked_offset]);
}

VALUE
ytl_code_current_pos(VALUE self)
{
  struct CodeSpace *raw_cs;

  raw_cs = (struct CodeSpace *)DATA_PTR(self);
  return INT2NUM(raw_cs->used);
}

VALUE
ytl_code_set_current_pos(VALUE self, VALUE val)
{
  struct CodeSpace *raw_cs;

  raw_cs = (struct CodeSpace *)DATA_PTR(self);
  raw_cs->used = NUM2INT(val);
  return val;
}

VALUE
ytl_code_base_address(VALUE self)
{
  struct CodeSpace *raw_cs;

  raw_cs = (struct CodeSpace *)DATA_PTR(self);
  return UINT2NUM((unsigned long)raw_cs->body);
}

VALUE
ytl_code_call(int argc, VALUE *argv, VALUE self)
{
  VALUE addr;
  VALUE args;
  VALUE rc;
  void *raddr;

  rb_scan_args(argc, argv, "11", &addr, &args);
  raddr = (void *)NUM2ULONG(addr);

#ifdef __x86_64__
  asm("mov %1, %%rax;"
      "call *%2;"
      "mov %%rax, %0;"
      : "=r"(rc) 
      : "r"(args), "r"(raddr) 
      : "%rax");
#elif  __i386__
  asm("mov %1, %%eax;"
      "call *%2;"
      "mov %%eax, %0;"
      : "=r"(rc) 
      : "r"(args), "r"(raddr) 
      : "%eax");
#else
#error "only i386 or x86_64 is supported"
#endif

  return rc;
}
  
VALUE
ytl_code_space_code(VALUE self)
{
  struct CodeSpace *raw_cs;

  raw_cs = (struct CodeSpace *)DATA_PTR(self);

  return rb_str_new(raw_cs->body, raw_cs->used);
}  

VALUE
ytl_code_space_to_s(VALUE self)
{
  struct CodeSpace *raw_cs;

  raw_cs = (struct CodeSpace *)DATA_PTR(self);

  return rb_sprintf("#<codeSpace %p base=%p:...>", (void *)self, (void *)raw_cs->body);
}

static VALUE *
get_registers(unsigned long *regs, VALUE *argv)
{
  argv[0] = ULONG2NUM((unsigned long)__builtin_return_address(1));

  /* regs[0]   old bp
     regs[-1]  old ebx (maybe gcc depend)
     regs[-2]  return address
     regs[-3]  pusha starts
  */
  argv[1] = ULONG2NUM(regs[-3]);   /* eax */
  argv[2] = ULONG2NUM(regs[-4]);   /* ecx */
  argv[3] = ULONG2NUM(regs[-5]);   /* edx */
  argv[4] = ULONG2NUM(regs[-6]);   /* ebx */
  argv[5] = ULONG2NUM(regs[-7]);   /* ebp */
  argv[6] = ULONG2NUM(regs[-8]);   /* esi */
  argv[7] = ULONG2NUM(regs[-9]);   /* edi */

  return argv;
}

static void
body(void)
{
  VALUE *argv;
  unsigned long *regs;

  asm("mov (%%ebp), %0"
      : "=r" (regs) : : "%eax");
  argv = ALLOCA_N(VALUE, 8);
  argv = get_registers(regs, argv);

  rb_funcall2(ytl_eStepHandler, ytl_v_step_handler_id, 8, argv);
}

static void
pushall(void)
{
#ifdef __x86_64__
  asm("push %rax");
  asm("push %rcx");
  asm("push %rdx");
  asm("push %rbx");
  asm("push %rbp");
  asm("push %rsi");
  asm("push %rdi");
#elif __i386__
  asm("pushal");
#else
#error "only i386 or x86_64 is supported"
#endif
}

static void
popall(void)
{
#ifdef __x86_64__
  asm("pop %rdi");
  asm("pop %rsi");
  asm("pop %rbp");
  asm("pop %rbx");
  asm("pop %rdx");
  asm("pop %rcx");
  asm("pop %rax");
#elif __i386__
  asm("popal");
#else
#error "only i386 or x86_64 is supported"
#endif
}
void
ytl_step_handler()
{

  /* Don't add local variables. Maybe break consistency of stack */

  pushall();
  body();
  popall();
}

void 
Init_ytljit() 
{
  VALUE *argv;

  ytl_mYTLJit = rb_define_module("YTLJit");

  rb_define_module_function(ytl_mYTLJit, "address_of", ytl_address_of, 1);
  rb_define_module_function(ytl_mYTLJit, "memref", ytl_memref, 1);

  ytl_v_step_handler_id = rb_intern("step_handler");

  ytl_cStepHandler = rb_define_class_under(ytl_mYTLJit, "StepHandler", rb_cObject);
  argv = ALLOCA_N(VALUE, 1);
  ytl_eStepHandler = rb_class_new_instance(0, argv, ytl_cStepHandler);

  ytl_cCodeSpace = rb_define_class_under(ytl_mYTLJit, "CodeSpace", rb_cObject);
  rb_define_alloc_func(ytl_cCodeSpace, ytl_code_space_allocate);
  rb_define_method(ytl_cCodeSpace, "[]=", ytl_code_space_emit, 2);
  rb_define_method(ytl_cCodeSpace, "[]", ytl_code_space_ref, 1);
  rb_define_method(ytl_cCodeSpace, "current_pos", ytl_code_current_pos, 0);
  rb_define_method(ytl_cCodeSpace, "current_pos=", ytl_code_set_current_pos, 1);
  rb_define_method(ytl_cCodeSpace, "base_address", ytl_code_base_address, 0);
  rb_define_method(ytl_cCodeSpace, "call", ytl_code_call, -1);
  rb_define_method(ytl_cCodeSpace, "code", ytl_code_space_code, 0);
  rb_define_method(ytl_cCodeSpace, "to_s", ytl_code_space_to_s, 0);

  /* Open Handles */
  OPEN_CHECK(dl_handles[used_dl_handles] = dlopen(NULL, RTLD_LAZY));
  used_dl_handles++;
}

