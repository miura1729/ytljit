require 'test/unit'
require 'lib/ytljit/ytljit.rb'

class InstructionTests < Test::Unit::TestCase
  include YTLJit

  def setup
    @asm = Assembler.new
    @eax = OpEAX.instance
    @ecx = OpECX.instance
    @lit32 = OpImmidiate32.new(0x123456780)
    @in_eax = OpIndirect.new(@eax)
    @in_eax_125 = OpIndirect.new(@eax, OpImmidiate8.new(125))
  end

  def test_add
    assert_equal(@asm.add(@eax, @lit32), [5, 0x123456780].pack("CL"))
    assert_equal(@asm.add(@ecx, @lit32), [0x81, 0xC1, 0x123456780].pack("CCL"))
    assert_equal(@asm.add(@ecx, @eax), [3, 0xC8].pack("CC"))
    assert_equal(@asm.add(@eax, @in_eax), [3, 0].pack("CC"))
    assert_equal(@asm.add(@eax, @in_eax_125), [3, 0x40, 125].pack("C3"))

    assert_equal(@asm.mov(@eax, @lit32), [0xB8, 0x123456780].pack("CL"))
  end
end
