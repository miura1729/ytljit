#include <setjmp.h>
#include <dlfcn.h>
#include <unistd.h>
#include <stdlib.h>
#include "ruby.h"
#include "ruby/st.h"

#include "ytljit.h"
#include "thread.h"

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

static rb_method_entry_t*
search_method(VALUE klass, ID id)
{
    st_data_t body;
    if (!klass) {
	return 0;
    }

    while (!st_lookup(RCLASS_M_TBL(klass), id, &body)) {
	klass = RCLASS_SUPER(klass);
	if (!klass) {
	    return 0;
	}
    }

    return (rb_method_entry_t *)body;
}

VALUE 
ytl_method_address_of(VALUE klass, VALUE mname)
{
  rb_method_entry_t *me;
  ID mid = SYM2ID(mname);

  me = search_method(klass, mid);

  if (me && me->def && me->def->type == VM_METHOD_TYPE_CFUNC) {
    return ULONG2NUM((uintptr_t)me->def->body.cfunc.func);
  }
  else {
    return Qnil;
  }
}

VALUE 
ytl_instance_var_address_of(VALUE slf, VALUE ivname)
{
  ID ivid = SYM2ID(ivname);
  struct st_table *iv_index_tbl;
  VALUE *valadd, *ptr;
  long len;
  st_data_t index;

  len = ROBJECT_NUMIV(slf);
  ptr = ROBJECT_IVPTR(slf);
  iv_index_tbl = ROBJECT_IV_INDEX_TBL(slf);
  if (!iv_index_tbl) return Qnil;
  if (!st_lookup(iv_index_tbl, (st_data_t)ivid, &index)) return Qnil;
  if (len <= (long)index) return Qnil;
  valadd = &ptr[index];
  return ULONG2NUM((uintptr_t)valadd);
}

void *
ytl_method_address_of_raw(VALUE klass, VALUE mname)
{
  rb_method_entry_t *me;
  ID mid = SYM2ID(mname);

  me = search_method(klass, mid);

  if (me && me->def && me->def->type == VM_METHOD_TYPE_CFUNC) {
      return (void *)me->def->body.cfunc.func;
  }
  else {
    return NULL;
  }
}

VALUE
ytl_binding_to_a(VALUE self)
{
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
  rb_iseq_t *iseq;

  GetProcPtr(self, proc);
  iseq = proc->block.iseq;
  if (proc->is_from_method) {
    NODE *node = (NODE *)iseq;
    /* method(:foo).to_proc */
    iseq = rb_method_get_iseq(node->u2.value);
  }
  if (iseq) {
    return iseq->self;
  }
  else {
    return Qnil;
  }
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
  return ULONG2NUM(*((uintptr_t *)NUM2LONG(addr)));
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
    //memcpy(new_cs, raw_cs, newsize / 2);
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
  asm("push %%rbx;"
      "push %%rdi;"
      "push %%rsi;"
      "push %%r12;"
      "push %%r13;"
      "push %%r14;"
      "push %%r15;"
      "mov %1, %%rax;"
      "call *%2;"
      "mov %%rax, %0;"
      "pop  %%r15;"
      "pop  %%r14;"
      "pop  %%r13;"
      "pop  %%r12;"
      "pop  %%rsi;"
      "pop  %%rdi;"
      "pop  %%rbx;"
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

#ifdef __x86_64__
#define NUMREGS 16
#elif  __i386__
#define NUMREGS 8
#else
#error "only i386 or x86-64 is supported"
#endif

static void
body(uintptr_t *regbuf)
{
  VALUE *argv;
  uintptr_t sp;
  int i;

  argv = ALLOCA_N(VALUE, NUMREGS + 1);

  for (i = 0; i < NUMREGS; i++) {
    argv[i] = ULONG2NUM((uintptr_t)regbuf[NUMREGS - i - 1]);
  }
  sp = (uintptr_t)regbuf;
  sp += NUMREGS * sizeof(uintptr_t); /* reg save area */
  sp += sizeof(uintptr_t); 	/* stored pc by call instruction */
  argv[NUMREGS] = ULONG2NUM(sp);

  rb_funcall2(ytl_eStepHandler, ytl_v_step_handler_id, NUMREGS + 1, argv);
}

void
ytl_backtrace(VALUE rip, 
	      VALUE rax, VALUE rcx, VALUE rdx, VALUE rbx, 
	      VALUE rbp, VALUE rsp, VALUE rdi, VALUE rsi
#ifdef __x86_64__
	      , VALUE r8, VALUE r9, VALUE r10, VALUE r11, 
	      VALUE r12, VALUE r13, VALUE r14, VALUE r15
#endif
	      ) 
{
  VALUE *argv;
  uintptr_t sp;

  argv = ALLOCA_N(VALUE, NUMREGS + 1);

  argv[0] = ULONG2NUM(rax);
  argv[1] = ULONG2NUM(rip);
  argv[2] = ULONG2NUM(rcx);
  argv[3] = ULONG2NUM(rdx);
  argv[4] = ULONG2NUM(rbx);
  argv[5] = ULONG2NUM(rbp);
  argv[6] = ULONG2NUM(rdi);
  argv[7] = ULONG2NUM(rsi);
#ifdef __x86_64__
  argv[8] = ULONG2NUM(r8); 
  argv[9] = ULONG2NUM(r9); 
  argv[10] = ULONG2NUM(r10); 
  argv[11] = ULONG2NUM(r11); 
  argv[12] = ULONG2NUM(r12); 
  argv[13] = ULONG2NUM(r13); 
  argv[14] = ULONG2NUM(r14); 
  argv[15] = ULONG2NUM(r15); 
#endif
  sp = (uintptr_t)rsp;
  sp += NUMREGS * sizeof(uintptr_t); /* reg save area */
  sp += sizeof(uintptr_t); 	/* stored pc by call instruction */
  argv[NUMREGS] = ULONG2NUM(sp);

  rb_funcall2(ytl_eStepHandler, ytl_v_step_handler_id, NUMREGS + 1, argv);
}

static uintptr_t * __attribute__ ((noinline, optimize("omit-frame-pointer")))
pushall(void)
{
#ifdef __x86_64__
  asm("pop %rax");
  asm("push %rcx");
  asm("push %rdx");
  asm("push %rbx");
  asm("push %rbp");
  asm("push %rsi");
  asm("push %rdi");
  asm("push %r8");
  asm("push %r9");
  asm("push %r10");
  asm("push %r11");
  asm("push %r12");
  asm("push %r13");
  asm("push %r14");
  asm("push %r15");
  asm("mov  %rax, %rcx");	/* return %rsp */
  asm("mov  %rsp, %rax");	/* return %rsp */
  asm("push %rcx");
#elif __i386__
  asm("pop %eax");
  asm("push %ecx");
  asm("push %edx");
  asm("push %ebx");
  asm("push %ebp");
  asm("push %esi");
  asm("push %edi");
  asm("mov  %eax, %ecx");	/* return %rsp */
  asm("mov  %esp, %eax");	/* return %rsp */
  asm("push %ecx");
#else
#error "only i386 or x86-64 is supported"
#endif
}

static void __attribute__ ((noinline, optimize("omit-frame-pointer")))
popall(void)
{
#ifdef __x86_64__
  asm("pop %rax");
  asm("pop %r15");
  asm("pop %r14");
  asm("pop %r13");
  asm("pop %r12");
  asm("pop %r11");
  asm("pop %r10");
  asm("pop %r9");
  asm("pop %r8");
  asm("pop %rdi");
  asm("pop %rsi");
  asm("pop %rbp");
  asm("pop %rbx");
  asm("pop %rdx");
  asm("pop %rcx");
  asm("push %rax");
#elif __i386__
  asm("pop %eax");
  asm("pop %edi");
  asm("pop %esi");
  asm("pop %ebp");
  asm("pop %ebx");
  asm("pop %edx");
  asm("pop %ecx");
  asm("push %eax");
#else
#error "only i386 or x86-64 is supported"
#endif
}

void __attribute__ ((optimize("omit-frame-pointer")))
ytl_step_handler()
{
#ifdef __x86_64__
  asm("push %rax");
  asm("add $0x8, %rsp");
  asm("mov %0, %%rax" : : "g"(__builtin_return_address(0)));
  asm("sub $0x8, %rsp");
  asm("push %rax");
  body(pushall());
  popall();
  asm("pop %rax");
  asm("pop %rax");
#elif __i386__
  asm("push %eax");
  asm("add $0x4, %esp");
  asm("mov %0, %%eax" : : "g"(__builtin_return_address(0)));
  asm("sub $0x4, %esp");
  asm("push %eax");
  body(pushall());
  popall();
  asm("pop %eax");
  asm("pop %eax");
#else
#error "only i386 or x86-64 is supported"
#endif
}

VALUE 
ytl_ivar_get_boxing(VALUE slf, int off)
{
  VALUE *ivptr;
  VALUE rval;

  ivptr = ROBJECT_IVPTR(slf);
  rval = ivptr[off];
  if (rval != Qundef) {
    return rval;
  }
  else {
    return Qnil;
  }
}

VALUE 
ytl_ivar_set_boxing(VALUE slf, int off, VALUE val)
{
  int len;
  int i;

  /* Copy from variable.c in ruby1.9 */
  len = ROBJECT_NUMIV(slf);
  if (len <= off) {
    VALUE *ptr = ROBJECT_IVPTR(slf);
    if (off < ROBJECT_EMBED_LEN_MAX) {
      RBASIC(slf)->flags |= ROBJECT_EMBED;
      ptr = ROBJECT(slf)->as.ary;
      for (i = 0; i < ROBJECT_EMBED_LEN_MAX; i++) {
	ptr[i] = Qundef;
      }
    }
    else {
      VALUE *newptr;
      long newsize = (off+1) + (off+1)/4; /* (index+1)*1.25 */
      if (RBASIC(slf)->flags & ROBJECT_EMBED) {
	newptr = ALLOC_N(VALUE, newsize);
	MEMCPY(newptr, ptr, VALUE, len);
	RBASIC(slf)->flags &= ~ROBJECT_EMBED;
	ROBJECT(slf)->as.heap.ivptr = newptr;
      }
      else {
	REALLOC_N(ROBJECT(slf)->as.heap.ivptr, VALUE, newsize);
	newptr = ROBJECT(slf)->as.heap.ivptr;
      }
      for (; len < newsize; len++)
	newptr[len] = Qundef;
      ROBJECT(slf)->as.heap.numiv = newsize;
    }
  }
  ROBJECT_IVPTR(slf)[off] = val;

  return val;
}

void 
Init_ytljit_ext() 
{
  VALUE *argv;

  init_csarena();

  ytl_mYTLJit = rb_define_module("YTLJit");

  rb_define_module_function(ytl_mYTLJit, "address_of", ytl_address_of, 1);
  rb_define_module_function(rb_cObject, "method_address_of", 
			    ytl_method_address_of, 1);
  rb_define_method(rb_cObject, "instance_var_address_of", 
			    ytl_instance_var_address_of, 1);
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
  
  ytl_mRuntime = rb_define_module_under(ytl_mYTLJit, "Runtime");
  ytl_cArena = rb_define_class_under(ytl_mRuntime, "Arena", rb_cObject);
  rb_define_alloc_func(ytl_cArena, ytl_arena_allocate);
  rb_define_method(ytl_cArena, "[]=", ytl_arena_emit, 2);
  rb_define_method(ytl_cArena, "[]", ytl_arena_ref, 1);
  rb_define_method(ytl_cArena, "size", ytl_arena_size, 0);
  rb_define_method(ytl_cArena, "body_address", ytl_arena_address, 0);
  rb_define_method(ytl_cArena, "raw_address", ytl_arena_raw_address, 0);
  rb_define_method(ytl_cArena, "to_s", ytl_arena_to_s, 0);

  ytl_cThread = rb_define_class_under(ytl_mRuntime, "Thread", rb_cObject);
  rb_define_method(ytl_cThread, "_join", ytl_thread_join, 0);
  rb_define_method(ytl_cThread, "_merge", ytl_thread_merge, 1);
  rb_define_method(ytl_cThread, "pself", ytl_thread_pself, 0);
  rb_define_method(ytl_cThread, "pself=", ytl_thread_set_pself, 1);
  rb_define_method(ytl_cThread, "cself", ytl_thread_cself, 0);

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

