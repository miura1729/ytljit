require 'test/unit'
require '../lib/ytljit.rb'

class CodeSpaceTests < Test::Unit::TestCase
  include YTLJit

  def test_emit
    cs    = CodeSpace.new
    cs[0] = "Hello"
    assert_equal(cs.code, "Hello")
    cs.emit("World")
    assert_equal(cs.code, "HelloWorld")
  end

  def test_ref
    cs    = CodeSpace.new
    cs[0] = "Hello"
    assert_equal(cs[1], 'e'.ord)
    p cs.base_address.to_s(16)
  end

  def test_withasm
    asm   = Assembler.new(cs = CodeSpace.new)
    func  =cs.base_address
    # registor definition
    eax   = OpEAX.instance
    esp   = OpESP.instance
    hello = OpImmidiate32.new("Hello World".address)
    asm.mov(eax, hello)
    asm.push(eax)
    # rbp = address_of("rb_xx") #YAY!
    rbp = address_of("rb_p") #YAY!
    asm.call(rbp)
    asm.add(esp, OpImmidiate8.new(4))
    asm.ret
    cs.call(func)
  end

  def test_resize
    cs = CodeSpace.new

    cs[0] = "Hello"
    assert_equal(cs[0][0], 'H'.ord)

    cs[32] = "Hello"
    assert_equal(cs[32][1], 'e'.ord)

    cs[64] = "Hello"
    assert_equal(cs[2], 'l'.ord)

    cs[128] = "Hello"
    assert_equal(cs[3], 'l'.ord)

    cs[256] = "Hello"
    assert_equal(cs[4], 'o'.ord)

    cs[768] = "Hello"
    assert_equal(cs[4], 'o'.ord)

    cs[2000] = "Hello"
    assert_equal(cs[4], 'o'.ord)

    cs[4096] = "Hello"
    assert_equal(cs[4], 'o'.ord)

    cs[8155] = "Hello"
    assert_equal(cs[4], 'o'.ord)

=begin
#Large Memory area not support
    cs[10920] = "Hello"
    assert_equal(cs[4], 'o'.ord)

    cs[32768] = "Hello"
    assert_equal(cs[4], 'o'.ord)

    cs[65520] = "Hello"
    assert_equal(cs[4], 'o'.ord)
=end
  end

  def test_manyspace
    cs = []
    100.times do
      cs = []
      100.times do |i|
        cs.push CodeSpace.new
        cs.last[4090] = "Hello"
        cs.push CodeSpace.new
        cs.last[90] = "Hello"
      end
      GC.start

      321.times do |i|
        cs.push CodeSpace.new
        cs.last[18] = "Hello"
        cs.push CodeSpace.new
        cs.last[289] = "Hello"
      end
    end
    assert_equal(cs.last[293], 'o'.ord)
  end
end
