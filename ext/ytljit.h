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

VALUE ytljit_address_of(VALUE, VALUE);
VALUE ytljit_code_space_allocate(VALUE);

extern VALUE cYTLJit;
extern VALUE cCodeSpace;

