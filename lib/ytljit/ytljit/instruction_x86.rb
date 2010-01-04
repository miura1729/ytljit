module YTLJit
  class OpReg8<OpRegistor
  end

  class OpAL<OpReg8
    def reg_no
      0
    end
  end

  class OpCL<OpReg8
    def reg_no
      1
    end
  end

  class OpDL<OpReg8
    def reg_no
      2
    end
  end

  class OpBL<OpReg8
    def reg_no
      3
    end
  end

  class OpReg32<OpRegistor
  end

  class OpEAX<OpReg32
    def reg_no
      0
    end
  end
  
  class OpECX<OpReg32
    def reg_no
      1
    end
  end
  
  class OpEDX<OpReg32
    def reg_no
      2
    end
  end
  
  class OpEBX<OpReg32
    def reg_no
      3
    end
  end

  class OpESP<OpReg32
    def reg_no
      4
    end
  end

  class OpEBP<OpReg32
    def reg_no
      5
    end
  end

  class OpESI<OpReg32
    def reg_no
      6
    end
  end
  
  class OpEDI<OpReg32
    def reg_no
      7
    end
  end

  module AssemblerUtil
    def modrm(dst, src)
      case dst
      when Fixnum
        p src
        case src
        when OpRegistor
          0b11000000 | ((dst & 7) << 3) | src.reg_no
        end
      when OpRegistor
        case src
        when OpRegistor
          0b11000000 | (dst.reg_no << 3) | src.reg_no
        end
      end
    end
  end
  
  class Assembler
    include AssemblerUtil

    def common_operand(dst, src, bopc, optc)
      case dst 
      when OpReg8
        case src
        when OpImmidiate8
          if dst.class == OpAL then
            [bopc + 0x4, src.value].pack("C2")
          else
            [0x80, modrm(optc, dst), src.value].pack("C2")
          end
          
        when OpReg8
          [bopc, modrm(dst, src)].pack("C2")

        else
          raise IlligalOperand, "Add instruction can\'t apply #{src} as src"
        end

      when OpReg32
        case src
        when OpImmidiate8
          [0x83, modrm(optc, dst), src.value].pack("C2")

        when OpImmidiate32
          if dst.class == OpEAX then
            [bopc + 0x5, src.value].pack("CL")
          else
            [0x81, modrm(optc, dst), src.value].pack("C2L")
          end

        when OpReg32
          [bopc + 0x3, modrm(dst, src)].pack("C2")

        when OpMem32
          [bopc + 0x03, modrm(dst, src)].pack("CL")

        else
          raise IlligalOperand, "ADD instruction can\'t apply #{src} as src"
        end

      when OpMem32
        case src
        when OpImmidiate8
          [0x83, modrm(optc, src), dst.value].pack("C2")

        when OpImmidiate32
          [0x81, modrm(optc, src), dst.value].pack("CL")

        when OpReg32
          [bopc + 0x1, modrm(dst, src)].pack("C2")

        else
          raise IlligalOperand, "ADD instruction can\'t apply #{src} as src"
        end
      end
    end

    def adc(dst, src)
      common_operand(dst, src, 0x0, 0x2)
    end

    def add(dst, src)
      common_operand(dst, src, 0x0, 0x0)
    end

    def and(dst, src)
      common_operand(dst, src, 0x20, 0x4)
    end

    def cmp(dst, src)
      common_operand(dst, src, 0x38, 0x7)
    end
  end
end
