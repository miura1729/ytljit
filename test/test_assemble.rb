require 'test/unit'
require 'lib/ytljit/ytljit.rb'

class InstructionTests < Test::Unit::TestCase
  include YTLJit

  def setup
    @asm = Assembler.new
    @eax = OpEAX.instance
    @ecx = OpECX.instance
    @lit32 = OpImmidiate32.new(0x12345678)
    @in_eax = OpIndirect.new(@eax)
    @in_eax_125 = OpIndirect.new(@eax, OpImmidiate8.new(125))
    @in_eax_4096 = OpIndirect.new(@eax, OpImmidiate32.new(4096))
  end

  def test_add
    assert_equal(@asm.add(@eax, @lit32), [5, 0x12345678].pack("CL"))
    assert_equal(@asm.add(@ecx, @lit32), [0x81, 0xC1, 0x12345678].pack("CCL"))
    assert_equal(@asm.add(@ecx, @eax), [3, 0xC8].pack("CC"))
    assert_equal(@asm.add(@eax, @in_eax), [3, 0].pack("CC"))
    assert_equal(@asm.add(@eax, @in_eax_125), [3, 0x40, 125].pack("C3"))
    assert_equal(@asm.add(@in_eax_4096, @eax), [1, 0x80, 0, 0x10, 0, 0].pack("C*"))

    assert_equal(@asm.mov(@eax, @lit32), [0xB8, 0x12345678].pack("CL"))
    assert_equal(@asm.mov(@eax, @in_eax_125), [0x8B, 0x40, 0x7d].pack("C3"))
    assert_equal(@asm.mov(@in_eax_125, @eax), [0x89, 0x40, 0x7d].pack("C3"))
    File.open("foo.bin", "w") {|fp|
      fp.write @asm.add(@eax, @in_eax_125)
      fp.write @asm.add(@in_eax_125, @eax)
      fp.write @asm.add(@in_eax_4096, @eax)
      fp.write @asm.sub(@eax, @in_eax_125)
      fp.write @asm.and(@in_eax_125, @eax)
      fp.write @asm.or(@in_eax_4096, @eax)
      fp.write @asm.xor(@in_eax_4096, @eax)
      fp.write @asm.cmp(@in_eax_4096, @eax)
      fp.write @asm.mov(@eax, @lit32)
      fp.write @asm.mov(@eax, @in_eax_125)
      fp.write @asm.mov(@in_eax_125, @eax)
      fp.write @asm.push(@eax)
      fp.write @asm.pop(@in_eax_125)
    }
  end
end
