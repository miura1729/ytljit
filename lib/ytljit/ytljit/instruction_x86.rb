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

  class OpReg64<OpRegistor
  end

  class OpRAX<OpReg64
    def reg_no
      0
    end
  end

  class OpRBX<OpReg64
    def reg_no
      1
    end
  end

  class OpRCX<OpReg64
    def reg_no
      2
    end
  end

  class OpRDX<OpReg64
    def reg_no
      3
    end
  end

  class OpRDI<OpReg64
    def reg_no
      4
    end
  end

  class OpRSI<OpReg64
    def reg_no
      5
    end
  end

  class OpRBP<OpReg64
    def reg_no
      6
    end
  end

  class OpRSP<OpReg64
    def reg_no
      7
    end
  end

  class OpR8<OpReg64
    def reg_no
      8
    end
  end

  class OpR9<OpReg64
    def reg_no
      9
    end
  end

  class OpR10<OpReg64
    def reg_no
      10
    end
  end

  class OpR11<OpReg64
    def reg_no
      11
    end
  end

  class OpR12<OpReg64
    def reg_no
      12
    end
  end

  class OpR13<OpReg64
    def reg_no
      13
    end
  end

  class OpR14<OpReg64
    def reg_no
      14
    end
  end

  class OpR15<OpReg64
    def reg_no
      15
    end
  end
  
  module AssemblerUtilX86Modrm
    def modrm_indirect(reg, rm)
      regv = nil
      case reg
      when Integer
        regv = reg
        
      else
        regv = reg.value
      end

      case rm.disp
      when 0
        fstb = 0b00000000 | ((regv & 7) << 3) | rm.reg.reg_no
        if rm.reg.is_a?(OpESP) then
          [[fstb, 0x24], "C2"]
        else
          [[fstb], "C"]
        end
        
      when OpImmidiate8
        fstb = 0b01000000 | ((regv & 7) << 3) | rm.reg.reg_no
        if rm.reg.is_a?(OpESP) then
          [[fstb, 0b00100100, rm.disp.value], "C3"]
        else
          [[fstb, rm.disp.value], "CC"]
        end
        
      when OpImmidiate32
        fstb = 0b10000000 | ((regv & 7) << 3) | rm.reg.reg_no
        if rm.reg.is_a?(OpESP) then
          [[fstb, 0b00100100, rm.disp.value], "C2L"]
        else
          [[fstb, rm.disp.value], "CL"]
        end

      when Integer
        fstb = 0b10000000 | ((regv & 7) << 3) | rm.reg.reg_no
        if rm.reg.is_a?(OpESP) then
          [[fstb, 0b00100100, rm.disp], "C2L"]
        else
          [[fstb, rm.disp], "CL"]
        end
      end
    end

    def modrm(inst, reg, rm, dst, src, src2 = nil)
      case reg
      when Integer
        case rm
        when OpRegistor
          [[0b11000000 | ((reg & 7) << 3) | rm.reg_no], "C"]

        when OpIndirect
          modrm_indirect(reg, rm)

        else
          return nosupported_addressing_mode(inst, dst, src, src2)
        end

      when OpRegistor
        case rm
        when OpRegistor
          [[0b11000000 | (reg.reg_no << 3) | rm.reg_no], "C"]

        when OpIndirect
          modrm_indirect(reg, rm)
        end

      else
          return nosupported_addressing_mode(inst, dst, src, src2)
      end
    end
  end

  module AssemblerUtilX86
    case RbConfig::CONFIG["target_cpu"] 
    when /i?86/
      include AssemblerUtilX86Modrm
    end

    def nosupported_addressing_mode(inst, dst, src, src2 = nil)
      mess = "Not supported addessing mode in #{inst} #{dst} #{src} #{src2}"
      raise IlligalOperand, mess
    end

    def common_operand_80(dst, src, bopc, optc, inst)
      case dst 
      when OpReg8
        case src
        when OpImmidiate8, Integer
          if dst.class == OpAL then
            [bopc + 0x4, src.value].pack("C2")
          else
            modseq, modfmt = modrm(inst, optc, dst, dst, src)
            ([0x80] + modseq + [src.value]).pack("C#{modfmt}C")
          end
          
        when OpReg8
          modseq, modfmt = modrm(inst, dst, src, dst, src)
          ([bopc] + modseq).pack("C#{modfmt}")

        else
          return nosupported_addressing_mode(inst, dst, src)
        end

      when OpReg32
        case src
        when OpImmidiate8
          modseq, modfmt = modrm(inst, optc, dst, dst, src)
          ([0x83] + modseq + [src.value]).pack("C#{modfmt}C")

        when OpImmidiate32, Integer
          srcv = nil
          if src.is_a?(Integer)
            srcv = src
          else
            srcv = src.value
          end
          if dst.class == OpEAX then
            [bopc + 0x5, srcv].pack("CL")
          else
            modseq, modfmt = modrm(inst, optc, dst, dst, src)
            ([0x81] + modseq + [srcv]).pack("C#{modfmt}L")
          end

        when OpReg32, OpMem32, OpIndirect
          modseq, modfmt = modrm(inst, dst, src, dst, src)
          ([bopc + 0x03] + modseq).pack("C#{modfmt}")

        else
          return nosupported_addressing_mode(inst, dst, src)
        end

      when OpIndirect
        case src
        when OpImmidiate8
          modseq, modfmt = modrm(inst, optc, src, dst, src)
          ([0x83] + modseq + [dst.value]).pack("C#{modfmt}")

        when OpImmidiate32, Integer
          modseq, modfmt = modrm(inst, optc, src, dst, src)
          ([0x81] + modseq + [dst.value]).pack("C#{modfmt}L")

        when OpReg32
          modseq, modfmt = modrm(inst, src, dst, dst, src)
          ([bopc + 0x1] + modseq).pack("C#{modfmt}")

        else
          return nosupported_addressing_mode(inst, dst, src)
        end
      end
    end

    def common_jcc(addr, opc, lopc, inst)
      addr2 = addr
      if addr.is_a?(OpImmidiate32) then
        addr2 = addr.value
      end
      offset = addr2 - @asm.current_address - 2
      if offset > -128 and offset < 127 and false then
        [opc, offset].pack("C2")
      else
        offset = addr2 - @asm.current_address - 6
        [0x0F, lopc, offset].pack("C2L")
      end
    end

    def common_shift(dst, optc, shftnum, inst)
      modseq, modfmt = modrm(inst, optc, dst, dst, shftnum)
      if shftnum.is_a?(OpImmidiate8) then
        shftnum = shftnum.value
      end

      if shftnum == 1 then
        ([0xD1] + modseq ).pack("C#{modfmt}")
      else
        ([0xC1] + modseq + [shftnum]).pack("C#{modfmt}C")
      end
    end
  end
  
  class GeneratorX86Binary<Generator
    include AssemblerUtilX86

    def initialize(asm, handler = "ytl_step_handler")
      super(asm)
      @step_handler = address_of(handler)
    end

    def call_stephandler
      if @asm.step_mode
        call(@step_handler)
      else
        ""
      end
    end

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
        when OpImmidiate8, Integer
          [0xB0 + dst.reg_no, src.value].pack("C2")
          
        when OpReg8
          modseq, modfmt = modrm(:mov, dst, src, dst, src)
          ([0x88] + modseq).pack("C#{modfmt}")

        when OpIndirect
          modseq, modfmt = modrm(:mov, dst, src, dst, src)
          ([0x8A] + modseq).pack("C#{modfmt}")

        else
          return nosupported_addressing_mode(:mov, dst, src)
        end
          
      when OpReg32
        case src
        when OpImmidiate32, Integer
          [0xB8 + dst.reg_no, src.value].pack("CL")

        when OpReg32
          modseq, modfmt = modrm(:mov, src, dst, dst, src)
          ([0x89] + modseq).pack("C#{modfmt}")

        when  OpIndirect
          modseq, modfmt = modrm(:mov, dst, src, dst, src)
          ([0x8B] + modseq).pack("C#{modfmt}")
          
        else
          return nosupported_addressing_mode(:mov, dst, src)
        end
      
      when OpIndirect
        case src
        when OpReg8
          modseq, modfmt = modrm(:mov, src, dst, dst, src)
          ([0x88] + modseq).pack("C#{modfmt}")

        when OpReg32
          modseq, modfmt = modrm(:mov, src, dst, dst, src)
          ([0x89] + modseq).pack("C#{modfmt}")

        when OpImmidiate8
          modseq, modfmt = modrm(:mov, 0, dst, dst, src)
          ([0xC6] + modseq + [src.value]).pack("C#{modfmt}C")

        when OpImmidiate32
          modseq, modfmt = modrm(:mov, 0, dst, dst, src)
          ([0xC7] + modseq + [src.value]).pack("C#{modfmt}L")

        when Integer
          modseq, modfmt = modrm(:mov, 0, dst, dst, src)
          ([0xC7] + modseq + [src]).pack("C#{modfmt}L")

        else
          return nosupported_addressing_mode(:mov, dst, src)
        end
        
      else
        return nosupported_addressing_mode(:mov, dst, src)
      end
    end

    def lea(dst, src)
      if !dst.is_a?(OpReg32)
        return nosupported_addressing_mode(:lea, dst, src)
      end

      if !src.is_a?(OpIndirect)
        return nosupported_addressing_mode(:lea, dst, src)
      end

      modseq, modfmt = modrm(:lea, dst, src, dst, src)
      ([0x8D] + modseq).pack("C#{modfmt}")
    end

    def push(dst)
      case dst
      when OpReg32
        [0x50 + dst.reg_no].pack("C")
        
      when OpIndirect
        modseq, modfmt = modrm(:push, 6, dst, dst, nil)
        ([0xFF] +  modseq).pack("C#{modfmt}")
        
      else
        return nosupported_addressing_mode(:push, dst, nil)
      end
    end

    def pop(dst)
      case dst
      when OpReg32
        [0x58 + dst.reg_no].pack("C")
        
      when OpIndirect
        modseq, modfmt = modrm(:pop, 0, dst, dst, nil)
        ([0x8F] +  modseq).pack("C#{modfmt}")
        
      else
        return nosupported_addressing_mode(:pop, dst, nil)
      end
    end

    def ja(addr)
      common_jcc(addr, 0x77, 0x87, :ja)
    end

    def jae(addr)
      common_jcc(addr, 0x73, 0x83, :jae)
    end

    def jb(addr)
      common_jcc(addr, 0x72, 0x82, :jb)
    end

    def jbe(addr)
      common_jcc(addr, 0x76, 0x86, :jbe)
    end

    def jl(addr)
      common_jcc(addr, 0x7c, 0x8c, :jl)
    end

    def jle(addr)
      common_jcc(addr, 0x7e, 0x8e, :jle)
    end

    def jna(addr)
      common_jcc(addr, 0x76, 0x86, :jna)
    end

    def jnae(addr)
      common_jcc(addr, 0x72, 0x82, :jnae)
    end

    def jnb(addr)
      common_jcc(addr, 0x73, 0x83, :jnb)
    end

    def jnbe(addr)
      common_jcc(addr, 0x77, 0x87, :jnbe)
    end

    def jnc(addr)
      common_jcc(addr, 0x73, 0x83, :jnc)
    end

    def jnle(addr)
      common_jcc(addr, 0x7f, 0x8f, :jnle)
    end

    def jno(addr)
      common_jcc(addr, 0x71, 0x81, :jno)
    end

    def jo(addr)
      common_jcc(addr, 0x70, 0x80, :jo)
    end

    def jz(addr)
      common_jcc(addr, 0x74, 0x84, :jz)
    end

    def jnz(addr)
      common_jcc(addr, 0x75, 0x85, :jnz)
    end

    def jmp(addr)
      addr2 = addr
      if addr.is_a?(OpImmidiate32) then
        addr2 = addr.value
      end
      case addr2
      when Integer
        offset = addr2 - @asm.current_address - 2
        if offset > -128 and offset < 127 then
          [0xeb, offset].pack("C2")
        else
          offset = addr2 - @asm.current_address - 5
          [0xe9, offset].pack("CL")
        end
      else
        modseq, modfmt = modrm(:jmp, 4, addr2, addr2, nil)
        ([0xff] + modseq).pack("C#{modfmt}")
      end
    end

    def call(addr)
      case addr
      when Integer
        offset = addr - @asm.current_address - 5
        [0xe8, offset].pack("CL")

      when OpImmidiate32
        offset = addr.value - @asm.current_address - 5
        [0xe8, offset].pack("CL")

      else
        modseq, modfmt = modrm(:call, 2, addr, nil, addr)
        ([0xff] + modseq).pack("C#{modfmt}")
      end
    end

    def ret
      [0xc3].pack("C")
    end

    def sal(dst, shftnum = 1)
      common_shift(dst, 4, shftnum, :sal)
    end

    def sar(dst, shftnum = 1)
      common_shift(dst, 7, shftnum, :sar)
    end

    def shl(dst, shftnum = 1)
      common_shift(dst, 4, shftnum, :shl)
    end

    def shr(dst, shftnum = 1)
      common_shift(dst, 5, shftnum, :shr)
    end

    def rcl(dst, shftnum = 1)
      common_shift(dst, 2, shftnum, :rcl)
    end

    def rcr(dst, shftnum = 1)
      common_shift(dst, 3, shftnum, :rcr)
    end

    def rol(dst, shftnum = 1)
      common_shift(dst, 0, shftnum, :rol)
    end

    def ror(dst, shftnum = 1)
      common_shift(dst, 1, shftnum, :ror)
    end

    def imul(dst, src = nil, src2 = nil)
      case dst 
      when OpReg8, OpMem8
        if src == nil then
          modseq, modfmt = modrm(:imul, 5, dst, dst, 5)
          return ([0xF6] + modseq).pack("C#(modfmt}")
        end

      when OpIndirect, OpMem32
        if src != nil then
          modseq, modfmt = modrm(:imul, 5, dst, dst, 5)
          return ([0xF7] + modseq).pack("C#(modfmt}")
        end

      when OpReg32
        case src
        when nil
          modseq, modfmt = modrm(:imul, 5, dst, dst, 5)
          return ([0xF7] + modseq).pack("C#(modfmt}")
          
        when OpReg32, OpMem32, OpIndirect
          modseq, modfmt = modrm(:imul, dst, src, dst, src, src2)
          case src2 
          when nil
            return ([0x0F, 0xAF] + modseq).pack("C2#{modfmt}")
            
          when OpImmidiate8
            return ([0x6B] + modseq + [src2.value]).pack("C#{modfmt}C")

          when OpImmidiate32
            return ([0x69] + modseq + [src2.value]).pack("C#{modfmt}L")

          when Integer
            return ([0x69] + modseq + [src2]).pack("C#{modfmt}L")
          end

        when OpImmidiate8
          modseq, modfmt = modrm(:imul, dst, dst, dst, src)
          return ([0x6B] + modseq + [src.value]).pack("C#{modfmt}C")
          
        
        when OpImmidiate32
          modseq, modfmt = modrm(:imul, dst, dst, dst, src)
          return ([0x69] + modseq + [src.value]).pack("C#{modfmt}L")

        when Integer
          modseq, modfmt = modrm(:imul, dst, dst, dst, src)
          return ([0x69] + modseq + [src]).pack("C#{modfmt}L")

        end
      end

      return nosupported_addressing_mode(:imul, dst, src, src2)
    end

    def int3
      [0xcc].pack("C")
    end
  end
end
