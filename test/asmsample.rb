require 'lib/ytljit/ytljit.rb'

include YTLJit

asm = Assembler.new

# registor definition
eax = OpEAX.instance
ecx = OpEAX.instance

asm.mov(eax, OpImmidiate32.new(0))
loop = asm.current_address
asm.add(eax, OpImmidiate8.new(1))
asm.jo(loop)
asm.ret

File.open("foo.bin", "w") {|fp|
  asm.flush(fp)
}
