require 'tempfile'
require 'rbconfig'
$ruby_platform = RUBY_PLATFORM
# $ruby_platform = "x86_64" #  You can select CPU type for debug.

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

require 'ytljit/codespace'

require "ext/ytljit.#{RbConfig::CONFIG['DLEXT']}"
