require 'mkmf'
$CFLAGS += ' -fomit-frame-pointer '
create_makefile("ytljit_ext");
