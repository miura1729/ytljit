enum ytl_thread_status {
  YTL_RUN = 0,
  YTL_SLEEP = 1,
  YTL_ABORTING = 2,
  YTL_DEAD = 3,
};

struct ytl_thread {
  enum ytl_thread_status status;
  pthread_t thread;
  pthread_attr_t attr;
};

extern VALUE ytl_thread_create(void *, void *(*)(void *));
extern VALUE ytl_thread_join(VALUE);
extern VALUE ytl_cThread;

