/* Allocator for code space */
#include <assert.h>
#include <unistd.h>
#include <sys/mman.h>
#include <stdlib.h>
#include "ruby.h"


/* CodeSpaceArena is memory area for allocate codespace
   CodeSpaceArena is same align and size. Current size is 16 Kbytes.
   Structure of CodeSpaceArea is following format

    Hi         16k |                           |
                   -----------------------------
                   |  allocation area          | 
         alocarea  |                           |
                   ----------------------------
		   | Gate Keeper  0xfffffff    |
                   ----------------------------
                   |  bitmap(1 free, 0 used)   |
                8  |                           |
                   -----------------------------
   Lo           0  | next_and_size             |

   next_and_size is following format
        63          43  0
         xxx .... xxxssss
    x is next arena. next arena is same as current allocation size.
    s is current allocation size. real size is 16 * 2**ssss.
*/

typedef struct {
  uintptr_t next_and_size;
  uint64_t bitmap[1];
}  CodeSpaceArena;

#define ARENA_SIZE 16 * 1024

/* 2 * 64 means header and gatekeeper */
#define BITMAP_SIZE(ALOCSIZ) \
  (((ARENA_SIZE) * 8 - 2 * 64) / ((ALOCSIZ) * 8 + 1))

/* Last "+ 1" means gatekeeper */
#define HEADER_SIZE(ALOCSIZ) \
  (((BITMAP_SIZE(ALOCSIZ) + 63) / 64) + 1)

#define ALOCSIZLOG_MAX  10

static int csarena_allocarea_tab[ALOCSIZLOG_MAX] = {
  HEADER_SIZE(16),
  HEADER_SIZE(32),
  HEADER_SIZE(64),
  HEADER_SIZE(128),
  HEADER_SIZE(256),
  HEADER_SIZE(512),
  HEADER_SIZE(1024),
  HEADER_SIZE(2048),
  HEADER_SIZE(4096),
  HEADER_SIZE(8192),
};

static CodeSpaceArena *arena_tab[ALOCSIZLOG_MAX];
static CodeSpaceArena *arena_search_tab[ALOCSIZLOG_MAX];

static size_t page_size;

CodeSpaceArena *
alloc_arena(size_t aloclogsiz, CodeSpaceArena *prev_csa)
{
  uint64_t rbitmap;
  CodeSpaceArena *arena;
  void *newmem;
  int allocsiz;
  int bitmap_size;
  int allff_size;
  int rest_size;
  
#if !defined(__CYGWIN__)
  if (posix_memalign(&newmem, ARENA_SIZE, ARENA_SIZE)) {
    rb_raise(rb_eNoMemError, "Can't allocate code space area");
  }
  if(mprotect(newmem, ARENA_SIZE, PROT_READ | PROT_WRITE | PROT_EXEC)) {
    rb_raise(rb_eNoMemError, "mprotect failed");
  }
  arena = (CodeSpaceArena *)newmem;
#else
  if (!(arena = memalign(ARENA_SIZE, ARENA_SIZE))) {
    rb_raise(rb_eNoMemError, "Can't allocate code space area");
  }
#endif
  
  arena->next_and_size = ((uintptr_t)prev_csa) | aloclogsiz;

  /* fill bitmap: 1 means free */
  allocsiz = 16 << aloclogsiz;
  bitmap_size = BITMAP_SIZE(allocsiz);
  allff_size = (bitmap_size / 64) * 8;
  memset(arena->bitmap, 0xff, allff_size);
  
  /* rest of bit */
  rest_size = bitmap_size - allff_size * 8;
  rbitmap = (1 << (rest_size)) - 1;
  //fprintf(stderr, "%x %x \n", csarena_allocarea_tab[aloclogsiz], bitmap_size);
  arena->bitmap[csarena_allocarea_tab[aloclogsiz] - 2] = rbitmap;
  /* gatekeeper bit */
  arena->bitmap[csarena_allocarea_tab[aloclogsiz] - 1] = 0xff;

  return arena;
}

/*   Ref. Beautiful Code (Japanese ver) Page. 158 
     http://chessprogramming.wikispaces.com/Population+Count 
     Ypsilon Scheme System (src/bit.cpp)
 */
inline int
popcount(uint64_t x)
{
  x = x - ((x >> 1) & 0x5555555555555555ull);
  x = (x & 0x3333333333333333ull) + ((x >> 2) & 0x3333333333333333ull);
  x = (x + (x >> 4)) & 0x0f0f0f0f0f0f0f0full;
  x *= 0x0101010101010101ull;
  return x >> 56;
}

/* Ref. Hacker's dilight (Japanese ver) Page.86 */
inline int
ffs64(uint64_t x)
{
  x = x | (x << 1);
  x = x | (x << 2);
  x = x | (x << 4);
  x = x | (x << 8);
  x = x | (x << 16);
  x = x | (x << 32);
  return popcount(~x);
}

/* from Ypsilon Scheme System */
inline int
bytes_to_bucket(int x)
{
  uint32_t n = 0;
  uint32_t c = 16;
  x = x - 1;
  do {
    uint32_t y = x >> c;
    if (y != 0) { n = n + c; x = y; }
    c = c >> 1;
  } while (c != 0);
  return n + x - 4;
}

void *
search_free_chunk(CodeSpaceArena *arena)
{
  char *alocarea;
  CodeSpaceArena *new_arena;
  int i;
  int alocarea_off;
  int cbitmap;
  int logsize;

  logsize = arena->next_and_size & 0xf;
  alocarea_off = csarena_allocarea_tab[logsize] - 1;

  while (arena) {
    for (i = 0;(cbitmap = arena->bitmap[i]) == 0; i++);
    if (i < alocarea_off) {
      arena_search_tab[logsize] = arena;

      /* found free chunk */
      int bitpos = ffs64(cbitmap);

      /* bitmap free -> used */
      // fprintf(stderr, "%x %x\n", bitpos, arena->bitmap[i]);
      arena->bitmap[i] = cbitmap & (cbitmap - 1);

      /* Compute chunk address */
      alocarea = (char *)(&arena->bitmap[alocarea_off + 1]);
      return (alocarea + (16 << logsize) * (i * 64 + bitpos));
    }

    /* Not found. Allocate new arena */
    new_arena = (CodeSpaceArena *)(arena->next_and_size & ~(0xf));
    if (new_arena == NULL) {
      arena = alloc_arena(logsize, arena_tab[logsize]);
      arena_tab[logsize] = arena_search_tab[logsize] = arena;
    }
    else {
      arena = new_arena;
    }
  }

  /* Here newver reach maybe...*/
  assert(0);
}

void *
csalloc(int size)
{
  int logsize;
  void *res;
  
  logsize = bytes_to_bucket(size);
  res = search_free_chunk(arena_search_tab[logsize]);
  //  fprintf(stderr, "%x \n", res);
  return res;
}

void
csfree(void *chunk)
{
  CodeSpaceArena *arena;
  CodeSpaceArena *tmpa;
  CodeSpaceArena *sarena;
  size_t offset;
  size_t alocoff;
  size_t bitpos;
  int logsize;
  int alocsize;

  arena = (CodeSpaceArena *)(((uintptr_t)chunk) & (~(ARENA_SIZE - 1)));
  logsize = arena->next_and_size & 0xf;
  alocsize = 16 << logsize;

  alocoff = csarena_allocarea_tab[logsize];
  offset =(uintptr_t) chunk - (uintptr_t)(&(arena->bitmap[alocoff]));
  if ((offset & (alocsize - 1)) != 0) {
    rb_raise(rb_eArgError, "Maybe free illgal chunk");
  }
  bitpos = offset / alocsize;

#if 0
  arena->bitmap[bitpos / 64] ^= (1 << (bitpos & (64 - 1)));
  if (arena->bitmap[bitpos / 64] & (1 << (bitpos & (64 - 1))) == 0) {
    rb_raise(rb_eArgError, "Maybe freeed chunk passed");
  }
#endif

  /* Update arena_search_tab */
  for (tmpa = arena_tab[logsize], sarena = arena_search_tab[logsize];
       tmpa != sarena;
       tmpa = (CodeSpaceArena *)(tmpa->next_and_size & (~0xf))) {
    if (tmpa == arena) {
      arena_search_tab[logsize] = tmpa;
      break;
    }
  }
}

void
init_csarena()
{
  int i;

#if defined(__APPLE__) && defined(__MACH__)   /* Mac OS X */
  page_size = getpagesize();
#elif  __CYGWIN__
  page_size = 4096;
#else
  page_size = sysconf(_SC_PAGESIZE);
#endif

  /* Check page_size is valid */
  if ((ARENA_SIZE / page_size) * page_size != ARENA_SIZE) {
    rb_raise(rb_eNoMemError, "Not support this architecture");
  }

  for (i = 0; i < ALOCSIZLOG_MAX; i++) {
    arena_search_tab[i] = arena_tab[i] = alloc_arena(i, NULL);
  }
}
