#include <setjmp.h>
#include <dlfcn.h>
#include <unistd.h>
#include <stdlib.h>
#include "ruby.h"

#include "ytljit.h"

VALUE ytl_mYTLJit;
VALUE ytl_cCodeSpace;
VALUE ytl_cValueSpace;
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
      return ULONG2NUM((uintptr_t)add);
    }
  }

  return Qnil;
}

VALUE 
ytl_method_address_of(VALUE self, VALUE klass, VALUE mname)
{
  rb_method_entry_t *me;
  ID mid = SYM2ID(mname);

  me = rb_method_entry(klass, mid);

  if (me && me->def && me->def->type == VM_METHOD_TYPE_CFUNC) {
      return ULONG2NUM((uintptr_t)me->def->body.cfunc.func);
  }
  else {
    return Qnil;
  }
}

VALUE
ytl_binding_to_a(VALUE self)
{
  rb_proc_t *proc;
  rb_binding_t *bptr;
  rb_env_t *env;
  VALUE resary;
  VALUE eleary;
  VALUE tmpenv;
  int i;

  GetBindingPtr(self, bptr);

  resary = rb_ary_new();

  tmpenv = bptr->env;
  while (tmpenv) {
    GetEnvPtr(tmpenv, env);
    eleary = rb_ary_new();
    rb_ary_push(eleary, env->block.self);

    for (i = 0; i <= env->local_size; i++) {
      rb_ary_push(eleary, env->env[i]);
    }
    rb_ary_push(resary, eleary);

    tmpenv = env->prev_envval;
  }

  return resary;
}

VALUE
ytl_binding_variables(VALUE self)
{
  rb_binding_t *bptr;
  rb_env_t *env;
  rb_iseq_t *iseq;
  VALUE resary;
  VALUE eleary;
  VALUE tmpenv;
  int i;

  GetBindingPtr(self, bptr);

  resary = rb_ary_new();
  
  tmpenv = bptr->env;
  while (tmpenv) {
    GetEnvPtr(tmpenv, env);
    eleary = rb_ary_new();
    iseq = env->block.iseq;
    if (iseq) {
      for (i = 0; i < iseq->local_table_size; i++) {
	ID lid = iseq->local_table[i];
	if (rb_is_local_id(lid)) {
	  rb_ary_push(eleary, ID2SYM(lid));
	}
      }
    }

    rb_ary_push(resary, eleary);
    tmpenv = env->prev_envval;
  }

  return resary;
}
  

VALUE
ytl_proc_to_iseq(VALUE self)
{
  rb_proc_t *proc;

  GetProcPtr(self, proc);
  return proc->block.iseq->self;
}

VALUE
ytl_proc_copy(VALUE self, VALUE procval)
{
    rb_proc_t *src, *dst;
    GetProcPtr(procval, src);
    GetProcPtr(self, dst);

    dst->block = src->block;
    dst->block.proc = procval;
    dst->blockprocval = src->blockprocval;
    dst->envval = src->envval;
    dst->safe_level = src->safe_level;
    dst->is_lambda = src->is_lambda;

    return self;
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
 
  obj = csalloc(INIT_CODE_SPACE_SIZE);
  obj->size = INIT_CODE_SPACE_SIZE - sizeof(struct CodeSpace);
  obj->used = 0;
  return Data_Wrap_Struct(klass, NULL, csfree, (void *)obj);
}

VALUE
ytl_value_space_allocate(VALUE klass)
{
  struct CodeSpace *obj;
 
  obj = csalloc(VALUE_SPACE_SIZE);
  obj->size = VALUE_SPACE_SIZE - sizeof(struct CodeSpace);
  obj->used = 0;
  return Data_Wrap_Struct(klass, NULL, csfree, (void *)obj);
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
    size_t newsize = (raw_cs->size + sizeof(struct CodeSpace)) * 2;
    void *new_cs = csalloc(newsize);

    //*(struct CodeSpace *)new_cs = *(struct CodeSpace *)raw_cs;
    memcpy(new_cs, raw_cs, newsize / 2);
    csfree(raw_cs);
    raw_cs = new_cs;
    raw_cs->size = newsize - sizeof(struct CodeSpace);
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
  return ULONG2NUM((unsigned long)raw_cs->body);
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
      : "%rax", "%rbx");
#elif  __CYGWIN__
  asm("mov %1, %%eax;"
      "call *%2;"
      "mov %%eax, %0;"
      : "=r"(rc) 
      : "r"(args), "r"(raddr) 
      : "%eax", "%ebx");
#elif  __i386__
  /* push %ebx ? */
  asm("mov %1, %%eax;"
      "call *%2;"
      "mov %%eax, %0;"
      : "=r"(rc) 
      : "r"(args), "r"(raddr) 
      : "%eax");
  /* pop %ebx ? */
#else
#error "only i386 or x86-64 is supported"
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

VALUE
ytl_value_space_to_s(VALUE self)
{
  struct CodeSpace *raw_cs;

  raw_cs = (struct CodeSpace *)DATA_PTR(self);

  return rb_sprintf("#<valueSpace %p base=%p:...>", (void *)self, (void *)raw_cs->body);
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

#if defined(__i386__) || defined(__i386)
  asm("mov (%%ebp), %0"
      : "=r" (regs) : : "%eax");
#elif defined(__x86_64__) || defined(__x86_64)
  asm("mov (%%rbp), %0"
      : "=r" (regs) : : "%rax");
#else
#error "only i386 or x86-64 is supported"
#endif
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
#error "only i386 or x86-64 is supported"
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
#error "only i386 or x86-64 is supported"
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

  init_csarena();

  ytl_mYTLJit = rb_define_module("YTLJit");

  rb_define_module_function(ytl_mYTLJit, "address_of", ytl_address_of, 1);
  rb_define_module_function(ytl_mYTLJit, "method_address_of", 
			    ytl_method_address_of, 2);
  rb_define_module_function(ytl_mYTLJit, "memref", ytl_memref, 1);

  rb_define_method(rb_cBinding, "to_a", ytl_binding_to_a, 0);
  rb_define_method(rb_cBinding, "variables", ytl_binding_variables, 0);

  rb_define_method(rb_cProc, "to_iseq", ytl_proc_to_iseq, 0);
  rb_define_method(rb_cProc, "copy", ytl_proc_copy, 1);

  ytl_v_step_handler_id = rb_intern("step_handler");

  ytl_cStepHandler = rb_define_class_under(ytl_mYTLJit, "StepHandler", rb_cObject);
  argv = ALLOCA_N(VALUE, 1);
  ytl_eStepHandler = rb_class_new_instance(0, argv, ytl_cStepHandler);
  rb_global_variable(&ytl_eStepHandler);

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

  ytl_cValueSpace = 
    rb_define_class_under(ytl_mYTLJit, "ValueSpace", ytl_cCodeSpace);
  rb_define_alloc_func(ytl_cValueSpace, ytl_value_space_allocate);
  rb_define_method(ytl_cValueSpace, "to_s", ytl_value_space_to_s, 0);

  
  
  /* Open Handles */
#ifdef __CYGWIN__
  OPEN_CHECK(dl_handles[used_dl_handles] = dlopen("cygwin1.dll", RTLD_LAZY));
  used_dl_handles++;
  OPEN_CHECK(dl_handles[used_dl_handles] = dlopen("cygruby191.dll", RTLD_LAZY));
  used_dl_handles++;
  OPEN_CHECK(dl_handles[used_dl_handles] = dlopen("ytljit.so", RTLD_LAZY));
  used_dl_handles++;
#else
  OPEN_CHECK(dl_handles[used_dl_handles] = dlopen(NULL, RTLD_LAZY));
  used_dl_handles++;
#endif
}

