#include <stdlib.h>
#include <pthread.h>
#include "ruby.h"

#include "ytljit.h"

void
ytl_therad_create(void *(*entry)(void *), void *argv)
{
  pthread_t thread;
  pthread_attr_t attr;

  pthread_attr_init(&attr);
  pthread_attr_setstacksize(&attr, 64 * 1024);
  pthread_create(&thread, &attr, entry, argv);
  pthread_join(thread, NULL);
  pthread_attr_destroy(&attr);
}
