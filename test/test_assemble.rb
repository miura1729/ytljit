require 'test/unit'
require '../lib/ytljit.rb'

include YTLJit
class InstructionTests < Test::Unit::TestCase
  def setup
    @cs = CodeSpace.new
    @asm = Assembler.new(@cs, GeneratorExtend)
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
    assert_equal(@asm.imul(@eax, @lit32), "i\xC0xV4\x12")
    assert_equal(@asm.imul(@eax, @ecx, @lit32), "i\xC1xV4\x12")
    assert_equal(@asm.imul(@eax, @in_eax_4096, @lit32), "i\x80\x00\x10\x00\x00xV4\x12")
#    @cs.disassemble
  end

  def test_mov
    assert_equal(@asm.mov(@eax, @lit32), [0xB8, 0x12345678].pack("CL"))
    assert_equal(@asm.mov(@eax, @in_eax_125), [0x8B, 0x40, 0x7d].pack("C3"))
    assert_equal(@asm.mov(@in_eax_125, @eax), [0x89, 0x40, 0x7d].pack("C3"))
    File.open("foo.bin", "w") {|fp|
# =begin
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
      st = AsmType::Struct.new(
                          AsmType::INT32, :foo,
                          AsmType::INT32, :bar,
                          AsmType::Struct.new(
                                 AsmType::INT32, :kkk,
                                 AsmType::INT32, :ass,
                                 AsmType::INT32, :baz,
                                            ), :aaa,
                           AsmType::INT32, :baz
                          )
      foo = TypedData.new(st, X86::EAX)
      cd, foo = @asm.mov(X86::EAX, foo[:baz])
      fp.write cd
# =end
    hello = OpImmidiate32.new("Hello World".address)
    rshello = TypedData.new(InternalRubyType::RString, hello)
      cd, foo = @asm.mov(X86::EAX, rshello[:as][:heap][:ptr])
    fp.write cd
    fp.write @asm.push(X86::EAX)
    rbp = address_of("puts")
    fp.write @asm.call(rbp)
    fp.write @asm.add(X86::ESP, OpImmidiate8.new(4))
    fp.write @asm.ret
    }
  end

  def test_struct
    st = AsmType::Struct.new(
                          AsmType::INT32, :foo,
                          AsmType::INT32, :bar,
                          AsmType::INT32, :baz
                          )
    foo = TypedData.new(st, X86::EAX)
    cd, type = @asm.mov(X86::EAX, foo[:baz])
    assert_equal(cd,
                 [0x8b, 0x80, 0x8, 0x0, 0x0, 0x0].pack("C*"))

     st = AsmType::Struct.new(
                          AsmType::INT32, :foo,
                          AsmType::INT32, :bar,
                          AsmType::Struct.new(
                                 AsmType::INT32, :kkk,
                                 AsmType::INT32, :ass,
                                 AsmType::INT32, :baz,
                                            ), :aaa,
                           AsmType::INT32, :baz
                          )
    foo = TypedData.new(st, X86::EBX)
    cd, type = @asm.mov(X86::EDX, foo[:aaa][:baz])
    assert_equal(cd,
                 [0x89, 0xd8, 0x8b, 0x80, 0x10, 0x0, 0x0, 0x0, 0x89, 0xc2].pack("C*"))
   end

  def test_callseq_macro
    @asm.mov(AbsArch::FUNC_ARG[0], OpImmidiate32.new(1))
    @asm.call_with_arg(OpImmidiate32.new(0), 1)
    @cs.disassemble
  end

  include X86
  def test_movss
    @asm.movss(XMM0, @in_esp_0)
    @asm.movss(XMM7, @in_esp_10)
    @asm.movss(@in_esp_10, XMM0)
    @asm.movsd(XMM0, @in_esp_0)
    @asm.movsd(XMM7, @in_esp_10)
    @asm.movsd(@in_esp_10, XMM0)
    @cs.disassemble
  end
end
