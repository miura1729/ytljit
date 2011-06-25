#include <unistd.h>
#include <stdlib.h>
#include "ruby.h"

#include "ytljit.h"

VALUE ytl_mRuntime;
VALUE ytl_cArena;

void
ytl_arena_mark(struct ArenaHeader *arenah)
{
  VALUE *base;
  VALUE *start;
  struct ArenaBody *bodyptr;
  struct ArenaBody *next_bodyptr;
  struct ArenaBody *lastbodyptr;
  VALUE *bodyeleptr;
  int appear;

  lastbodyptr = (struct ArenaBody *)(((uintptr_t)arenah->lastptr) & (~(ARENA_SIZE - 1)));
  appear = 0;

  for (bodyptr = arenah->body; bodyptr; bodyptr = next_bodyptr) {
    if (bodyptr == lastbodyptr) {
      start = arenah->lastptr;
      appear = 1;
    } 
    else if (appear)  {
      start = bodyptr->body;
    }
    else {
      next_bodyptr = bodyptr->next;
      arenah->body = next_bodyptr;
      free(bodyptr);
      continue;
    }

    base = bodyptr->body + (bodyptr->size / sizeof(VALUE));
    for (bodyeleptr = start; bodyeleptr < base; bodyeleptr++) {
      rb_gc_mark_maybe(*bodyeleptr);
    }
    next_bodyptr = bodyptr->next;
  }
}

void
ytl_arena_free(struct ArenaHeader *arenah)
{
  VALUE *base;
  VALUE *start;
  struct ArenaBody *curptr;
  struct ArenaBody *curptr_next;
  
  for (curptr = arenah->body; curptr; curptr = curptr_next) {
    curptr_next = curptr->next;
    free(curptr);
  }
  
  free(arenah);
}

#define DO_RETRY                                               \
do {                                                           \
  if (retry_mode) {                                            \
    rb_raise(rb_eNoMemError, "Can't allocate arena area");     \
  }                                                            \
  else {                                                       \
    retry_mode = 1;                                            \
    rb_gc();                                                   \
    goto retry;                                                \
  }                                                            \
} while(0)


struct ArenaBody *
ytl_arena_allocate_body()
{
  void *newmem;
  struct ArenaBody *abody;
  int retry_mode = 0;

 retry:

#if !defined(__CYGWIN__)
  if (posix_memalign(&newmem, ARENA_SIZE, ARENA_SIZE)) {
    DO_RETRY;
  }
  abody = (struct ArenaBody *)newmem;
#else
  if (!(abody = memalign(ARENA_SIZE, ARENA_SIZE))) {
    DO_RETRY;
  }
#endif

  abody->size = ARENA_SIZE - sizeof(struct ArenaBody);
  abody->next = 0;
  return abody;
}

VALUE
ytl_arena_allocate(VALUE klass)
{
  struct ArenaHeader *arenah;
  struct ArenaBody *arenab;

  arenah = malloc(sizeof(struct ArenaHeader));
  arenah->body = ytl_arena_allocate_body();
  arenab = arenah->body;
  arenab->header = arenah;
  arenah->lastptr = arenab->body + (arenab->size / sizeof(VALUE));

  return Data_Wrap_Struct(klass, ytl_arena_mark, ytl_arena_free, 
			  (void *)arenah);
}

char *
ytl_arena_alloca(char *stptr, int size)
{
  uintptr_t lsp;
  struct ArenaHeader *arenah;
  struct ArenaBody *oldbody;
  struct ArenaBody *bodyptr;
  struct ArenaBody *next_bodyptr;

  lsp = (uintptr_t)stptr;
  oldbody = (struct ArenaBody *)(lsp & (~(ARENA_SIZE -1)));
  arenah  = oldbody->header;
  size = size * 8;

  for (bodyptr = arenah->body; bodyptr != oldbody; bodyptr = next_bodyptr) {
    next_bodyptr = bodyptr->next;
    arenah->body = next_bodyptr;
    free(bodyptr);
  }

  if ((lsp & (ARENA_SIZE - 1)) < ((lsp - size - 64) & (ARENA_SIZE - 1))) {
    struct ArenaBody *arenab;

    arenah->lastptr = (void *)stptr;
    arenab = arenah->body = ytl_arena_allocate_body();
    if (arenab != oldbody) {
      arenab->next = oldbody;
    }
    arenab->header = arenah;
    arenah->lastptr = arenab->body + (arenab->size / sizeof(VALUE));
    stptr = (char *)arenah->lastptr;
  }
  stptr -= size;

  return stptr;
}

VALUE
ytl_arena_ref(VALUE self, VALUE offset)
{
  struct ArenaHeader *arenah;
  int raw_offset;

  Data_Get_Struct(self, struct ArenaHeader, arenah);
  raw_offset = (arenah->body->size / sizeof(VALUE)) - FIX2INT(offset);

  return ULONG2NUM(arenah->body->body[raw_offset]);
}

VALUE
ytl_arena_emit(VALUE self, VALUE offset, VALUE src)
{
  struct ArenaHeader *arenah;

  int raw_offset;
  int newsize;
  VALUE *newlastptr;

  Data_Get_Struct(self, struct ArenaHeader, arenah);
  raw_offset = (arenah->body->size / sizeof(VALUE)) - NUM2ULONG(offset);

  arenah->body->body[raw_offset] = FIX2INT(src);
  newlastptr = arenah->body->body + raw_offset;
  if (newlastptr < arenah->lastptr) {
    arenah->lastptr = newlastptr;
  }

  return src;
}

VALUE
ytl_arena_size(VALUE self)
{
  struct ArenaHeader *arenah;
  struct ArenaBody *arenab;

  int totsize;

  Data_Get_Struct(self, struct ArenaHeader, arenah);
  totsize = 0;
  for (arenab = arenah->body; arenab; arenab = arenab->next) {
    totsize += arenab->size;
  }

  return INT2FIX(totsize);
}

VALUE
ytl_arena_address(VALUE self)
{
  struct ArenaHeader *arenah;

  Data_Get_Struct(self, struct ArenaHeader, arenah);

  return ULONG2NUM((uintptr_t)arenah->body->body);
}

VALUE
ytl_arena_raw_address(VALUE self)
{
  struct ArenaHeader *arenah;

  Data_Get_Struct(self, struct ArenaHeader, arenah);

  return ULONG2NUM((uintptr_t)arenah);
}

VALUE
ytl_arena_to_s(VALUE self)
{
  struct ArenaHeader *arenah;

  Data_Get_Struct(self, struct ArenaHeader, arenah);

  return rb_sprintf("#<Arena %p size=%d body=%p last=%p>", 
		    (void *)self, 
		    ytl_arena_size(self) / 2,
		    (void *)arenah->body->body,
		    (void *)arenah->lastptr);
}
