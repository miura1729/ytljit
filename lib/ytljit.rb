require "rubygems"

require 'tempfile'
require 'rbconfig'
require 'pp'
if $ruby_platform == nil then
  $ruby_platform = RUBY_PLATFORM
end
# $ruby_platform = "x86_64" #  You can select CPU type for debug.

require 'iseq'

# require "ytljit_ext"
require_relative "../ext/ytljit_ext"


require_relative 'ytljit/codespace'

require_relative 'ytljit/marshal'
require_relative 'ytljit/util'
require_relative 'ytljit/error'

require_relative 'ytljit/asm'
require_relative 'ytljit/instruction'
require_relative 'ytljit/instruction_x86'
require_relative 'ytljit/instruction_x64'
require_relative 'ytljit/instruction_ia'
require_relative 'ytljit/type'
require_relative 'ytljit/struct'
require_relative 'ytljit/asmutil'
require_relative 'ytljit/asmext_x86'
require_relative 'ytljit/asmext_x64'
require_relative 'ytljit/asmext'

require_relative 'ytljit/rubyvm'

require_relative 'ytljit/vm_codegen'
require_relative 'ytljit/vm_inspect'
require_relative 'ytljit/vm_inline_method'

require_relative 'ytljit/vm'
require_relative 'ytljit/vm_sendnode'

require_relative 'ytljit/vm_trans'
require_relative 'ytljit/vm_type_gen'
require_relative 'ytljit/vm_type'

require_relative 'ytljit/vm_typeinf'
require_relative 'ytljit/vm_cruby_obj'

require_relative 'ytljit/arena'


# Runtime

require_relative 'runtime/object.rb'
require_relative 'runtime/gc.rb'

module YTLJit
  VERSION = "0.0.10"
end

