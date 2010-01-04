require 'test/unit'
require 'lib/ytljit/ytljit.rb'

class InstructionTests < Test::Unit::TestCase
  include YTLJit

  def setup
    @asm = Assembler.new
    @eax = OpEAX.instance
    @ecx = OpECX.instance
    @lit32 = OpImmidiate32.new(0x123456780)
  end

  def test_add
    assert_equal(@asm.add(@eax, @lit32), [5, 0x123456780].pack("CL"))
    assert_equal(@asm.add(@ecx, @lit32), [5, 5, 0x123456780].pack("CCL"))
  end
end
