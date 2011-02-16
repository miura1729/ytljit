#include <unistd.h>
#include <stdlib.h>
#include "ruby.h"

#include "ytljit.h"

VALUE ytl_mRuntime;
VALUE ytl_cArena;

void
ytl_arena_mark(struct Arena *raw_arena)
{
  VALUE *base;
  VALUE *start;
  VALUE *curptr;

  start = raw_arena->used;
  base = raw_arena->body + (raw_arena->size / sizeof(VALUE));
  for (curptr = start; curptr < base; curptr++) {
    //    printf("%x \n", *curptr);
    rb_gc_mark_maybe(*curptr);
  }
}

VALUE
ytl_arena_allocate(VALUE klass)
{
  struct Arena *arena;

  arena = malloc(ARENA_SIZE);
  arena->size = ARENA_SIZE - sizeof(struct Arena);
  arena->used = arena->body + (arena->size / sizeof(VALUE));

  return Data_Wrap_Struct(klass, ytl_arena_mark, free, (void *)arena);
}

VALUE
ytl_arena_ref(VALUE self, VALUE offset)
{
  struct Arena *raw_arena;
  int raw_offset;

  Data_Get_Struct(self, struct Arena, raw_arena);
  raw_offset = FIX2INT(offset);

  return ULONG2NUM(raw_arena->body[raw_offset]);
}

VALUE
ytl_arena_emit(VALUE self, VALUE offset, VALUE src)
{
  struct Arena *raw_arena;

  int raw_offset;

  Data_Get_Struct(self, struct Arena, raw_arena);
  raw_offset = NUM2ULONG(offset);

  raw_arena->body[raw_offset] = FIX2INT(src);

  return src;
}

VALUE
ytl_arena_size(VALUE self)
{
  struct Arena *raw_arena;

  int raw_offset;

  Data_Get_Struct(self, struct Arena, raw_arena);

  return INT2FIX(raw_arena->size);
}

VALUE
ytl_arena_address(VALUE self)
{
  struct Arena *raw_arena;

  Data_Get_Struct(self, struct Arena, raw_arena);

  return ULONG2NUM((uintptr_t)raw_arena->body);
}


VALUE
ytl_arena_to_s(VALUE self)
{
  struct Arena *raw_arena;

  Data_Get_Struct(self, struct Arena, raw_arena);

  return rb_sprintf("#<Arena %p size=%d body=%p>", 
		    (void *)self, 
		    raw_arena->size,
		    (void *)raw_arena->body);
}
