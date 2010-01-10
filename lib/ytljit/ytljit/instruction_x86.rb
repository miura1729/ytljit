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
    def modrm_indirect(dst, src)
      dstv = nil
      case dst
      when Fixnum
        dstv = dst
        
      else
        dstv = dst.value
      end

      case src.disp
      when 0
        [[0b00000000 | ((dstv & 7) << 3) | src.reg.reg_no], "C"]
        
      when OpImmidiate8
        [[(0b01000000 | ((dstv & 7) << 3) | src.reg.reg_no), src.disp.value], 
         "CC"]
        
      when OpImmidiate32
        [[(0b10000000 | ((dstv & 7) << 3) | src.reg.reg_no), src.disp.value],
         "CL"]
      end
    end

    def modrm(dst, src)
      case dst
      when Fixnum
        case src
        when OpRegistor
          [[0b11000000 | ((dst & 7) << 3) | src.reg_no], "C"]

        when OpIndirect
          modrm_indirect(dst, src)

        else
          raise IlligalOperand, "Unkown #{src}"
        end

      when OpRegistor
        case src
        when OpRegistor
          [[0b11000000 | (dst.reg_no << 3) | src.reg_no], "C"]

        when OpIndirect
          modrm_indirect(dst, src)
        end

      else
        raise IlligalOperand, "Unkown #{dst}"
      end
    end

    def common_operand_80(dst, src, bopc, optc, inst)
      case dst 
      when OpReg8
        case src
        when OpImmidiate8, Fixnum
          if dst.class == OpAL then
            [bopc + 0x4, src.value].pack("C2")
          else
            modseq, modfmt = modrm(optc, dst)
            ([0x80] + modseq + [src.value]).pack("C#{modfmt}C")
          end
          
        when OpReg8
          modseq, modfmt = modrm(dst, src)
          ([bopc] + modseq).pack("C#{modfmt}")

        else
          raise IlligalOperand, "#{inst} instruction can\'t apply #{src} as src"
        end

      when OpReg32
        case src
        when OpImmidiate8
          modseq, modfmt = modrm(optc, dst)
          ([0x83] + modseq + [src.value]).pack("C#{modfmt}C")

        when OpImmidiate32, Fixnum
          if dst.class == OpEAX then
            [bopc + 0x5, src.value].pack("CL")
          else
            modseq, modfmt = modrm(optc, dst)
            ([0x81] + modseq + [src.value]).pack("C#{modfmt}L")
          end

        when OpReg32
          modseq, modfmt = modrm(dst, src)
          ([bopc + 0x3] + modseq).pack("C#{modfmt}")

        when OpMem32
          modseq, modfmt = modrm(dst, src)
          ([bopc + 0x03] + modseq).pack("C#{modfmt}")

        when OpIndirect
          modseq, modfmt = modrm(dst, src)
          ([bopc + 0x03] + modseq).pack("C#{modfmt}")

        else
          raise IlligalOperand, "#{inst} instruction can\'t apply #{src} as src"
        end

      when OpIndirect
        case src
        when OpImmidiate8
          modseq, modfmt = modrm(optc, src)
          ([0x83] + modseq + [dst.value]).pack("C#{modfmt}")

        when OpImmidiate32, Fixnum
          modseq, modfmt = modrm(optc, src)
          ([0x81] + modseq + [dst.value]).pack("C#{modfmt}L")

        when OpReg32
          modseq, modfmt = modrm(src, dst)
          ([bopc + 0x1] + modseq).pack("C#{modfmt}")

        else
          raise IlligalOperand, "#{inst} instruction can\'t apply #{src} as src"
        end
      end
    end
  end
  
  class Assembler
    include AssemblerUtil

    def add(dst, src)
      common_operand_80(dst, src, 0x00, 0x0, :add)
    end

    def or(dst, src)
      common_operand_80(dst, src, 0x08, 0x1, :or)
    end
    
    def adc(dst, src)
      common_operand_80(dst, src, 0x00, 0x2, :adc)
    end

    def sbb(dst, src)
      common_operand_80(dst, src, 0x18, 0x3, :sbb)
    end

    def and(dst, src)
      common_operand_80(dst, src, 0x20, 0x4, :and)
    end

    def sub(dst, src)
      common_operand_80(dst, src, 0x28, 0x5, :sub)
    end

    def xor(dst, src)
      common_operand_80(dst, src, 0x30, 0x6, :xor)
    end

    def cmp(dst, src)
      common_operand_80(dst, src, 0x38, 0x7, :cmp)
    end

    def mov(dst, src)
      case dst
      when OpReg8
        case src
        when OpImmidiate8, Fixnum
          [0xB0 + dst.reg_no, src.value].pack("C2")
          
        when OpReg8
          modseq, modfmt = modrm(dst, src)
          ([0x88] + modseq).pack("C#{modfmt}")

        when OpIndirect
          modseq, modfmt = modrm(dst, src)
          ([0x8A] + modseq).pack("C#{modfmt}")

        else
          raise IlligalOperand, "mov instruction can\'t apply #{src} as src"
        end
          
      when OpReg32
        case src
        when OpImmidiate32, Fixnum
          [0xB8 + dst.reg_no, src.value].pack("CL")

        when OpReg32
          modseq, modfmt = modrm(dst, src)
          ([0x8A] + modseq).pack("C#{modfmt}")

        when  OpIndirect
          modseq, modfmt = modrm(dst, src)
          ([0x8B] + modseq).pack("C#{modfmt}")
          
        else
          raise IlligalOperand, "mov instruction can\'t apply #{src} as src"
        end
      
      when OpIndirect
        case src
        when OpReg8
          modseq, modfmt = modrm(src, dst)
          ([0x88] + modseq).pack("C#{modfmt}")

        when OpReg32
          modseq, modfmt = modrm(src, dst)
          ([0x89] + modseq).pack("C#{modfmt}")

        when OpImmidiate8
          modseq, modfmt = modrm(0, dst)
          ([0xC6] + modseq + [src.value]).pack("C#{modfmt}C")

        when OpImmidiate32, Fixnum
          modseq, modfmt = modrm(0, dst)
          ([0xC7] + modseq + [src.value]).pack("C#{modfmt}L")
        end
      end
    end

    def push(dst)
      case dst
      when OpReg32
        [0x50 + dst.reg_no].pack("C")
        
      when OpIndirect
        modseq, modfmt = modrm(6, dst)
        ([0xff] +  modseq).pack("C#{modfmt}")
        
      else
        raise IlligalOperand, "push instruction can\'t apply #{src} as src"
      end
    end

    def pop(dst)
      case dst
      when OpReg32
        [0x58 + dst.reg_no].pack("C")
        
      when OpIndirect
        modseq, modfmt = modrm(0, dst)
        ([0x8f] +  modseq).pack("C#{modfmt}")
        
      else
        raise IlligalOperand, "pop instruction can\'t apply #{src} as src"
      end
    end
  end
end
