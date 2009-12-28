#include <stdlib.h>
#include <dlfcn.h>
#include "ruby.h"

#include "ytljit.h"

VALUE cYTLJit;
VALUE cCodeSpace;

static void *dl_handles[MAX_DL_HANDLES];
static int used_dl_handles = 0;

VALUE 
ytljit_address_of(VALUE self, VALUE symstr)
{
  int i;
  char *sym;
  void *add;

  sym = StringValuePtr(symstr);
  for (i = 0; i < used_dl_handles; i++) {
    if ((add = dlsym(dl_handles[i], sym)) != NULL) {
      return ULONG2NUM((unsigned long)add);
    }
  }

  return Qnil;
}

VALUE
ytljit_code_space_allocate(VALUE klass)
{
  struct CodeSpace *obj;
 
  obj = malloc(sizeof(struct CodeSpace) + 256);
  obj->size = 256;
  obj->used = 0;
  return Data_Wrap_Struct(klass, NULL, NULL, (void *)obj);
}

void 
Init_ytljit() 
{
  cYTLJit = rb_define_module("YTLJit");

  cCodeSpace = rb_define_class_under(cYTLJit, "CodeSpace", rb_cObject);
  
  rb_define_module_function(cYTLJit, "address_of", ytljit_address_of, 1);

  /* Open Handles */
  OPEN_CHECK(dl_handles[used_dl_handles] = dlopen("cygwin1.dll", RTLD_LAZY));
  used_dl_handles++;
  OPEN_CHECK(dl_handles[used_dl_handles] = dlopen("cygruby191.dll", RTLD_LAZY));
  used_dl_handles++;
}

