#include <stdlib.h>
#include <pthread.h>
#include "ruby.h"

#include "ytljit.h"
#include "thread.h"

VALUE ytl_cThread;

static void
ytl_thread_mark(struct ytl_thread *th)
{
  rb_gc_mark(th->pself);
  rb_gc_mark(th->cself);
}

/* You may think arguments order is wrong. But it is correct.
  This is for efficient code. See SendThreadNewNode#compile in 
  github#ytl/lib/ytl/thread.rb 
*/
VALUE
ytl_thread_create(void *argv, void *(*entry)(void *))
{
  struct ytl_thread *th;

  th = malloc(sizeof(struct ytl_thread));
  th->pself = ((VALUE *)argv)[4];
  th->cself = ((VALUE *)argv)[3];
  pthread_attr_init(&th->attr);
  pthread_attr_setstacksize(&th->attr, 64 * 1024);
  pthread_create(&th->thread, &th->attr, entry, argv);

  //printf("%x %x \n", th->pself, th->cself);

  return Data_Wrap_Struct(ytl_cThread, ytl_thread_mark, NULL, (void *)th);
}

static void
ytl_obj_copy(VALUE dest, VALUE obj)
{
  rb_copy_generic_ivar(dest, obj);
  rb_gc_copy_finalizer(dest, obj);
  rb_copy_generic_ivar(dest, obj);
  rb_gc_copy_finalizer(dest, obj);
  switch (TYPE(obj)) {
  case T_OBJECT:
    if (!(RBASIC(dest)->flags & ROBJECT_EMBED) && ROBJECT_IVPTR(dest)) {
      xfree(ROBJECT_IVPTR(dest));
      ROBJECT(dest)->as.heap.ivptr = 0;
      ROBJECT(dest)->as.heap.numiv = 0;
      ROBJECT(dest)->as.heap.iv_index_tbl = 0;
    }
    if (RBASIC(obj)->flags & ROBJECT_EMBED) {
      MEMCPY(ROBJECT(dest)->as.ary, ROBJECT(obj)->as.ary, VALUE, ROBJECT_EMBED_LEN_MAX);
      RBASIC(dest)->flags |= ROBJECT_EMBED;
    }
    else {
      long len = ROBJECT(obj)->as.heap.numiv;
      VALUE *ptr = ALLOC_N(VALUE, len);
      MEMCPY(ptr, ROBJECT(obj)->as.heap.ivptr, VALUE, len);
      ROBJECT(dest)->as.heap.ivptr = ptr;
      ROBJECT(dest)->as.heap.numiv = len;
      ROBJECT(dest)->as.heap.iv_index_tbl = ROBJECT(obj)->as.heap.iv_index_tbl;
      RBASIC(dest)->flags &= ~ROBJECT_EMBED;
    }
    break;

#if 0    
  case T_CLASS:
  case T_MODULE:
    if (RCLASS_IV_TBL(dest)) {
      st_free_table(RCLASS_IV_TBL(dest));
      RCLASS_IV_TBL(dest) = 0;
    }
    if (RCLASS_CONST_TBL(dest)) {
      rb_free_const_table(RCLASS_CONST_TBL(dest));
      RCLASS_CONST_TBL(dest) = 0;
    }
    if (RCLASS_IV_TBL(obj)) {
      RCLASS_IV_TBL(dest) = st_copy(RCLASS_IV_TBL(obj));
    }
    break;
#endif
  }
}

void
ytl_thread_exit(VALUE val)
{
  pthread_exit((void *)val);
}

VALUE
ytl_thread_join(VALUE self)
{
  struct ytl_thread *th;

  Data_Get_Struct(self, struct ytl_thread, th);
  pthread_join(th->thread, NULL);
  pthread_attr_destroy(&th->attr);

  return self;
}

VALUE
ytl_thread_merge(VALUE self, VALUE newself)
{
  struct ytl_thread *th;
  Data_Get_Struct(self, struct ytl_thread, th);

  if (th->pself != newself) {
    ytl_obj_copy(th->pself, newself);
  }

  return self;
}

VALUE
ytl_thread_pself(VALUE self)
{
  struct ytl_thread *th;

  Data_Get_Struct(self, struct ytl_thread, th);
  return th->pself;
}

VALUE
ytl_thread_set_pself(VALUE self, VALUE val)
{
  struct ytl_thread *th;

  Data_Get_Struct(self, struct ytl_thread, th);
  th->pself = val;
  return val;
}

VALUE
ytl_thread_cself(VALUE self)
{
  struct ytl_thread *th;

  Data_Get_Struct(self, struct ytl_thread, th);
  return th->cself;
}
