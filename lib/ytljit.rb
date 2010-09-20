require "rubygems"

require 'tempfile'
require 'rbconfig'
if $ruby_platform == nil then
  $ruby_platform = RUBY_PLATFORM
end
# $ruby_platform = "x86_64" #  You can select CPU type for debug.

require 'iseq'

require "ytljit_ext"

require 'ytljit/codespace'

require 'ytljit/marshal'
require 'ytljit/util'
require 'ytljit/error'

require 'ytljit/asm'
require 'ytljit/instruction'
require 'ytljit/instruction_x86'
require 'ytljit/instruction_x64'
require 'ytljit/instruction_ia'
require 'ytljit/type'
require 'ytljit/struct'
require 'ytljit/asmutil'
require 'ytljit/asmext_x86'
require 'ytljit/asmext_x64'
require 'ytljit/asmext'

require 'ytljit/rubyvm'

require 'ytljit/vm_codegen'
require 'ytljit/vm_inspect'
require 'ytljit/vm'
require 'ytljit/vm_sendnode'
require 'ytljit/vm_trans'
require 'ytljit/vm_type'

require 'ytljit/vm_typeinf'
