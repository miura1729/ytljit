struct ytl_thread {
  pthread_t thread;
  pthread_attr_t attr;
};

extern VALUE ytl_thread_create(void *, void *(*)(void *));
extern VALUE ytl_thread_join(VALUE);
extern VALUE ytl_cThread;

