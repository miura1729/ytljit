require 'ytljit.rb'

include YTLJit

# sample for file output
def file_output
  File.open("foo.bin", "w") {|fp|
    asm = Assembler.new(FileOutputStream.new(fp))
    
    # registor definition
    eax = OpEAX.instance
    ecx = OpECX.instance
    
    asm.mov(eax, OpImmidiate32.new(0))
    loop = asm.var_current_address
    asm.add(eax, OpImmidiate8.new(1))
    asm.jo(loop)
    arynew = address_of("rb_ary_new")
    asm.call(arynew)
    asm.ret
  }
end

# Hello World
include AbsArch
def hello
  asm = Assembler.new(cs = CodeSpace.new)
  
  # registor definition
  hello = "Hello World".address
  asm.step_mode = true
  asm.with_retry do
    asm.mov(FUNC_ARG[0], hello)
    rbp = address_of("rb_p")
    asm.call_with_arg(rbp, 1)
    asm.ret
  end
  cs.fill_disasm_cache
  cs.disassemble
  cs.call(cs.base_address)
end
hello

# Hello World (Use puts)
def hello2
  csentry = CodeSpace.new
  asm = Assembler.new(cs = CodeSpace.new)
  
  # registor definition
  hello ="Hello World11234".address
#  asm.step_mode = true
  InternalRubyType::rstring_ptr(hello, csentry, cs)
  asm.with_retry do
    asm.mov(FUNC_ARG[0], TMPR)
    rbp = address_of("puts")
    asm.call_with_arg(rbp, 1)
    asm.ret
  end
  cs.disassemble
  csentry.disassemble
  csentry.call(csentry.base_address)
end
hello2

# Fib number
def fib(n)
  cs0 = CodeSpace.new
  cs1 = CodeSpace.new
  cs2 = CodeSpace.new
  
  asm = Assembler.new(cs0)
#  asm.step_mode = true
  ent = nil
  asm.with_retry do
    ent = cs1.var_base_address
    asm.mov(TMPR, OpImmidiate32.new(n))
    asm.call(ent)
    asm.add(TMPR, TMPR)
    asm.add(TMPR, OpImmidiate8.new(1))
    asm.ret
  end
  
  asm = Assembler.new(cs1)
#  asm.step_mode = true
  asm.with_retry do
    asm.cmp(TMPR, OpImmidiate32.new(2))
    asm.jl(cs2.var_base_address)
    asm.sub(TMPR, OpImmidiate32.new(1))
    asm.push(TMPR)
    asm.call(ent)
    asm.pop(TMPR2)
    asm.sub(TMPR2, OpImmidiate32.new(1))
    asm.push(TMPR)
    asm.mov(TMPR, TMPR2)
    asm.call(ent)
    asm.pop(TMPR2)
    asm.add(TMPR, TMPR2)
    asm.ret
  end
  
  asm = Assembler.new(cs2)
#  asm.step_mode = true
  asm.with_retry do
    asm.mov(TMPR, OpImmidiate32.new(1))
    asm.ret
  end

#  cs0.disassemble
#  cs1.disassemble
#  cs2.disassemble

  cs0.call(cs0.base_address)
end

(1..20).each do |i|
  p fib(i)
end
