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
def hello
  asm = Assembler.new(cs = CodeSpace.new)
  
  # registor definition
  eax = OpEAX.instance
  esp = OpESP.instance
  hello = OpImmidiate32.new("Hello World".address)
  asm.step_mode = true
  asm.with_retry do
    asm.mov(eax, hello)
    asm.push(eax)
    rbp = address_of("rb_p")
    asm.call(rbp)
    asm.add(esp, OpImmidiate8.new(4))
    asm.ret
  end
  cs.fill_disasm_cache
  cs.call(cs.base_address)
end
hello

# Hello World (Use puts)
def hello2
  csentry = CodeSpace.new
  asm = Assembler.new(cs = CodeSpace.new)
  
  # registor definition
  eax = OpEAX.instance
  esp = OpESP.instance
  hello = OpImmidiate32.new("Hello World11234".address)
  asm.step_mode = true
  RubyType::rstring_ptr(hello, csentry, cs)
  asm.with_retry do
    asm.push(eax)
    rbp = address_of("puts")
    asm.call(rbp)
    asm.add(esp, OpImmidiate8.new(4))
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
  
  # registor definition
  eax = OpEAX.instance
  ebx = OpEBX.instance
  esp = OpESP.instance

  asm = Assembler.new(cs0)
#  asm.step_mode = true
  ent = nil
  asm.with_retry do
    ent = cs1.var_base_address
    asm.mov(eax, OpImmidiate32.new(n))
    asm.call(ent)
    asm.add(eax, eax)
    asm.add(eax, OpImmidiate8.new(1))
    asm.ret
  end
  
  asm = Assembler.new(cs1)
#  asm.step_mode = true
  asm.with_retry do
    asm.cmp(eax, OpImmidiate32.new(2))
    asm.jl(cs2.var_base_address)
    asm.sub(eax, OpImmidiate32.new(1))
    asm.push(eax)
    asm.call(ent)
    asm.pop(ebx)
    asm.sub(ebx, OpImmidiate32.new(1))
    asm.push(eax)
    asm.mov(eax, ebx)
    asm.call(ent)
    asm.pop(ebx)
    asm.add(eax, ebx)
    asm.ret
  end
  
  asm = Assembler.new(cs2)
#  asm.step_mode = true
  asm.with_retry do
    asm.mov(eax, OpImmidiate32.new(1))
    asm.ret
  end

  cs0.call(cs0.base_address)
end

(1..20).each do |i|
  p fib(i)
end
