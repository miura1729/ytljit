#include <stdlib.h>
#include <pthread.h>
#include "ruby.h"

#include "ytljit.h"
#include "thread.h"

VALUE ytl_cThread;

/* You may think arguments order is wrong. But it is correct.
  This is for efficient code. See SendThreadNewNode#compile in 
  github#ytl/lib/ytl/thread.rb 
*/
VALUE
ytl_thread_create(void *argv, void *(*entry)(void *))
{
  struct ytl_thread *th;
  VALUE obj;

  th = malloc(sizeof(struct ytl_thread));
  th->pself = ((VALUE *)argv)[4];
  th->cself = ((VALUE *)argv)[3];
  pthread_attr_init(&th->attr);
  pthread_attr_setstacksize(&th->attr, 64 * 1024);
  pthread_create(&th->thread, &th->attr, entry, argv);
  printf("%x %x \n", th->pself, th->cself);

  return Data_Wrap_Struct(ytl_cThread, NULL, NULL, (void *)th);
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

