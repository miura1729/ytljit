require 'test/unit'
require 'lib/ytljit/ytljit.rb'

include YTLJit
class InstructionTests < Test::Unit::TestCase
  def setup
    @asm = Assembler.new(CodeSpace.new)
    @eax = OpEAX.instance
    @ecx = OpECX.instance
    @esp = OpESP.instance
    @lit32 = OpImmidiate32.new(0x12345678)
    @in_eax = OpIndirect.new(@eax)
    @in_eax_125 = OpIndirect.new(@eax, OpImmidiate8.new(125))
    @in_eax_4096 = OpIndirect.new(@eax, OpImmidiate32.new(4096))
    @in_esp_0 = OpIndirect.new(@esp)
    @in_esp_10 = OpIndirect.new(@esp, OpImmidiate8.new(-10))
  end

  def test_add

    assert_equal(@asm.add(@eax, @lit32), [5, 0x12345678].pack("CL"))
    assert_equal(@asm.add(@ecx, @lit32), [0x81, 0xC1, 0x12345678].pack("CCL"))
    assert_equal(@asm.add(@ecx, @eax), [3, 0xC8].pack("CC"))
    assert_equal(@asm.add(@eax, @in_eax), [3, 0].pack("CC"))
    assert_equal(@asm.add(@eax, @in_eax_125), [3, 0x40, 125].pack("C3"))
    assert_equal(@asm.add(@in_eax_4096, @eax), [1, 0x80, 0, 0x10, 0, 0].pack("C*"))
  end

  def test_mov
    assert_equal(@asm.mov(@eax, @lit32), [0xB8, 0x12345678].pack("CL"))
    assert_equal(@asm.mov(@eax, @in_eax_125), [0x8B, 0x40, 0x7d].pack("C3"))
    assert_equal(@asm.mov(@in_eax_125, @eax), [0x89, 0x40, 0x7d].pack("C3"))
    File.open("foo.bin", "w") {|fp|
      lab = @asm.current_address
      fp.write @asm.add(@eax, @in_eax_125)
      fp.write @asm.add(@in_eax_125, @eax)
      fp.write @asm.add(@in_eax_4096, @eax)
      fp.write @asm.sub(@eax, @in_eax_125)
      fp.write @asm.and(@in_eax_125, @eax)
      fp.write @asm.or(@in_eax_4096, @eax)
      lab2 = @asm.current_address
      fp.write @asm.xor(@in_eax_4096, @eax)
      fp.write @asm.cmp(@in_eax_4096, @eax)
      fp.write @asm.mov(@eax, @lit32)
      fp.write @asm.mov(@eax, @in_eax_125)
      fp.write @asm.mov(@in_eax_125, @eax)
      fp.write @asm.mov(@in_esp_0, @eax)
      fp.write @asm.mov(@in_esp_10, @eax)
      fp.write @asm.push(@eax)
      fp.write @asm.pop(@in_eax_125)
      fp.write @asm.call(lab)
      fp.write @asm.jo(lab)
      fp.write @asm.jl(lab2)
      fp.write @asm.lea(@eax, @in_esp_0)
      fp.write @asm.lea(@eax, @in_esp_10)
      fp.write @asm.sal(@eax)
      fp.write @asm.sar(@eax)
      fp.write @asm.shl(@eax)
      fp.write @asm.shr(@eax)
      fp.write @asm.sal(@eax, 2)
      fp.write @asm.sar(@eax, 2)
      fp.write @asm.shl(@eax, 2)
      fp.write @asm.shr(@eax, 2)

      fp.write @asm.rcl(@eax)
      fp.write @asm.rcr(@eax)
      fp.write @asm.rol(@eax)
      fp.write @asm.ror(@eax)
      fp.write @asm.rcl(@eax, 2)
      fp.write @asm.rcr(@eax, 2)
      fp.write @asm.rol(@eax, 2)
      fp.write @asm.ror(@eax, 2)
    }
  end
end
