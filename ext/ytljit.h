#define MAX_DL_HANDLES 10

#define OPEN_CHECK(COND)                                        \
do {                                                            \
      if ((COND) == NULL) {	                                \
	printf("Open failed %d handle", used_dl_handles);	\
      }                                                         \
 } while(0)

struct CodeSpace {
  int size;
  int used;
  char body[1];
};

VALUE ytl_address_of(VALUE, VALUE);
VALUE ytl_code_space_allocate(VALUE);

extern VALUE ytl_mYTLJit;
extern VALUE ytl_cCodeSpace;
extern VALUE ytl_cStepHandler;
extern VALUE ytl_eStepHandler;

