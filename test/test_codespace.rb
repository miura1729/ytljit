require 'test/unit'
require 'lib/ytljit/ytljit.rb'

class CodeSpaceTests < Test::Unit::TestCase
  include YTLJit

  def test_emit
    cs = CodeSpace.new
    cs[0] = "Hello"
    assert_equal(cs.to_s, "Hello")
    cs.emit("World")
    assert_equal(cs.to_s, "HelloWorld")
  end

  def test_ref
    cs = CodeSpace.new
    cs[0] = "Hello"
    assert_equal(cs[1], 'e'.ord)
    # p cs.base_address.to_s(16)
  end

  def test_withasm
    asm = Assembler.new(cs = CodeSpace.new)
  
    # registor definition
    eax = OpEAX.instance
    esp = OpESP.instance
    hello = OpImmidiate32.new("Hello World".address)
    asm.mov(eax, hello)
    asm.push(eax)
    rbp = address_of("rb_p")
    asm.call(rbp)
    asm.add(esp, OpImmidiate8.new(4))
    asm.ret
    cs.call(cs.base_address)
  end
end
