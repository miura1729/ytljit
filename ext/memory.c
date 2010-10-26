#include <unistd.h>
#include <stdlib.h>
#include "ruby.h"

#include "ytljit.h"

VALUE ytl_mRuntime;
VALUE ytl_cArena;

VALUE
ytl_arena_allocate(VALUE klass)
{
  struct Arena *arena;

  arena = malloc(ARENA_SIZE);
  arena->size = ARENA_SIZE - sizeof(struct Arena);

  return Data_Wrap_Struct(klass, NULL, free, (void *)arena);
}

VALUE
ytl_arena_ref(VALUE self, VALUE offset)
{
  struct Arena *raw_arena;
  int raw_offset;

  raw_arena = (struct Arena *)DATA_PTR(self);
  raw_offset = FIX2INT(offset);

  return INT2FIX(raw_arena->body[raw_offset]);
}

VALUE
ytl_arena_emit(VALUE self, VALUE offset, VALUE src)
{
  struct Arena *raw_arena;

  int raw_offset;

  raw_arena = (struct Arena *)DATA_PTR(self);
  raw_offset = FIX2INT(offset);

  raw_arena->body[raw_offset] = FIX2INT(src);

  return src;
}

VALUE
ytl_arena_size(VALUE self)
{
  struct Arena *raw_arena;

  int raw_offset;

  raw_arena = (struct Arena *)DATA_PTR(self);

  return INT2FIX(raw_arena->size);
}

VALUE
ytl_arena_address(VALUE self)
{
  struct Arena *raw_arena;

  int raw_offset;

  raw_arena = (struct Arena *)DATA_PTR(self);

  return INT2FIX(raw_arena->body);
}


