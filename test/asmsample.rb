require 'lib/ytljit/ytljit.rb'

include YTLJit

File.open("foo.bin", "w") {|fp|
  asm = Assembler.new(FileOutputStream.new(fp))
  
  # registor definition
  eax = OpEAX.instance
  ecx = OpECX.instance
  
  asm.mov(eax, OpImmidiate32.new(0))
  loop = asm.current_address
  asm.add(eax, OpImmidiate8.new(1))
  asm.jo(loop)
  arynew = address_of("rb_ary_new")
  asm.call(arynew)
  asm.ret
  
  asm.flush
}
