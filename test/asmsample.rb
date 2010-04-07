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
    mov(eax, hello)
    push(eax)
    rbp = address_of("rb_p")
    call(rbp)
    add(esp, OpImmidiate8.new(4))
    ret
  end
  cs.fill_disasm_cache
  cs.call(cs.base_address)
end
hello

# Hello World (Use puts)
def hello2
  asm = Assembler.new(cs = CodeSpace.new)
  
  # registor definition
  eax = OpEAX.instance
  esp = OpESP.instance
  hello = OpImmidiate32.new("Hello World1234".address)
  asm.step_mode = true
  asm.with_retry do
    rshello = TypedData.new(RubyType::RString, hello)
    mov(eax, rshello[:as][:heap][:ptr])
    push(eax)
    rbp = address_of("puts")
    call(rbp)
    add(esp, OpImmidiate8.new(4))
    ret
  end
  cs.disassemble
  cs.call(cs.base_address)
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
    mov(eax, OpImmidiate32.new(n))
    call(ent)
    add(eax, eax)
    add(eax, OpImmidiate8.new(1))
    ret
  end
  
  asm = Assembler.new(cs1)
#  asm.step_mode = true
  asm.with_retry do
    cmp(eax, OpImmidiate32.new(2))
    jl(cs2.var_base_address)
    sub(eax, OpImmidiate32.new(1))
    push(eax)
    call(ent)
    pop(ebx)
    sub(ebx, OpImmidiate32.new(1))
    push(eax)
    mov(eax, ebx)
    call(ent)
    pop(ebx)
    add(eax, ebx)
    ret
  end
  
  asm = Assembler.new(cs2)
#  asm.step_mode = true
  asm.with_retry do
    mov(eax, OpImmidiate32.new(1))
    ret
  end

  cs0.call(cs0.base_address)
end

(1..20).each do |i|
  p fib(i)
end
