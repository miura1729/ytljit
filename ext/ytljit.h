#define MAX_DL_HANDLES 10
#define INIT_CODE_SPACE_SIZE 64
#define VALUE_SPACE_SIZE (32 * 1024)

#define OPEN_CHECK(COND)                                        \
do {                                                            \
      if ((COND) == NULL) {	                                \
	printf("Open failed %d handle", used_dl_handles);	\
      }                                                         \
 } while(0)

struct CodeSpace {
  size_t  size;
  size_t  used;
  char body[1];
};

VALUE ytl_address_of(VALUE, VALUE);
VALUE ytl_code_space_allocate(VALUE);

void init_csarena();
void *csalloc(int);
void csfree(void *);

extern VALUE ytl_mYTLJit;
extern VALUE ytl_cCodeSpace;
extern VALUE ytl_cValueSpace;
extern VALUE ytl_cStepHandler;
extern VALUE ytl_eStepHandler;

