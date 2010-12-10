module YTLJit

  class OpReg8<OpRegistor
  end

  class OpAL<OpReg8
    def reg_no
      0
    end

    def to_as
      "%al"
    end
  end

  class OpCL<OpReg8
    def reg_no
      1
    end

    def to_as
      "%cl"
    end
  end

  class OpDL<OpReg8
    def reg_no
      2
    end

    def to_as
      "%dl"
    end
  end

  class OpBL<OpReg8
    def reg_no
      3
    end

    def to_as
      "%bl"
    end
  end

  class OpReg32<OpRegistor
  end

  class OpEAX<OpReg32
    def reg_no
      0
    end

    def to_as
      "%eax"
    end
  end
  
  class OpECX<OpReg32
    def reg_no
      1
    end

    def to_as
      "%ecx"
    end
  end
  
  class OpEDX<OpReg32
    def reg_no
      2
    end

    def to_as
      "%edx"
    end
  end
  
  class OpEBX<OpReg32
    def reg_no
      3
    end

    def to_as
      "%ebx"
    end
  end

  class OpESP<OpReg32
    def reg_no
      4
    end

    def to_as
      "%esp"
    end
  end

  class OpEBP<OpReg32
    def reg_no
      5
    end

    def to_as
      "%ebp"
    end
  end

  class OpESI<OpReg32
    def reg_no
      6
    end

    def to_as
      "%esi"
    end
  end
  
  class OpEDI<OpReg32
    def reg_no
      7
    end

    def to_as
      "%edi"
    end
  end

  class OpReg64<OpRegistor
  end

  class OpRAX<OpReg64
    def reg_no
      0
    end

    def to_as
      "%rax"
    end
  end

  class OpRCX<OpReg64
    def reg_no
      1
    end

    def to_as
      "%rcx"
    end
  end

  class OpRDX<OpReg64
    def reg_no
      2
    end

    def to_as
      "%rdx"
    end
  end

  class OpRBX<OpReg64
    def reg_no
      3
    end

    def to_as
      "%rbx"
    end
  end

  class OpRSP<OpReg64
    def reg_no
      4
    end

    def to_as
      "%rsp"
    end
  end

  class OpRBP<OpReg64
    def reg_no
      5
    end

    def to_as
      "%rbp"
    end
  end

  class OpRSI<OpReg64
    def reg_no
      6
    end

    def to_as
      "%rsi"
    end
  end

  class OpRDI<OpReg64
    def reg_no
      7
    end

    def to_as
      "%rdi"
    end
  end

  class OpR8<OpReg64
    def reg_no
      8
    end

    def to_as
      "%r8"
    end
  end

  class OpR9<OpReg64
    def reg_no
      9
    end

    def to_as
      "%r9"
    end
  end

  class OpR10<OpReg64
    def reg_no
      10
    end

    def to_as
      "%r10"
    end
  end

  class OpR11<OpReg64
    def reg_no
      11
    end

    def to_as
      "%r11"
    end
  end

  class OpR12<OpReg64
    def reg_no
      12
    end

    def to_as
      "%r12"
    end
  end

  class OpR13<OpReg64
    def reg_no
      13
    end

    def to_as
      "%r13"
    end
  end

  class OpR14<OpReg64
    def reg_no
      14
    end

    def to_as
      "%r14"
    end
  end

  class OpR15<OpReg64
    def reg_no
      15
    end

    def to_as
      "%r15"
    end
  end

  class OpRegXMM<OpRegistor
  end

  class OpRXMM0<OpRegXMM
    def reg_no
      0
    end

    def to_as
      "%xmm0"
    end
  end

  class OpRXMM1<OpRegXMM
    def reg_no
      1
    end

    def to_as
      "%xmm1"
    end
  end

  class OpRXMM2<OpRegXMM
    def reg_no
      2
    end

    def to_as
      "%xmm2"
    end
  end

  class OpRXMM3<OpRegXMM
    def reg_no
      3
    end

    def to_as
      "%xmm3"
    end
  end

  class OpRXMM4<OpRegXMM
    def reg_no
      4
    end

    def to_as
      "%xmm4"
    end
  end

  class OpRXMM5<OpRegXMM
    def reg_no
      5
    end

    def to_as
      "%xmm5"
    end
  end

  class OpRXMM6<OpRegXMM
    def reg_no
      6
    end

    def to_as
      "%xmm6"
    end
  end

  class OpRXMM7<OpRegXMM
    def reg_no
      7
    end

    def to_as
      "%xmm7"
    end
  end

  class OpRXMM8<OpRegXMM
    def reg_no
      8
    end

    def to_as
      "%xmm8"
    end
  end

  class OpRXMM9<OpRegXMM
    def reg_no
      9
    end

    def to_as
      "%xmm9"
    end
  end

  class OpRXMM10<OpRegXMM
    def reg_no
      10
    end

    def to_as
      "%xmm10"
    end
  end

  class OpRXMM11<OpRegXMM
    def reg_no
      11
    end

    def to_as
      "%xmm11"
    end
  end

  class OpRXMM12<OpRegXMM
    def reg_no
      12
    end

    def to_as
      "%xmm12"
    end
  end

  class OpRXMM13<OpRegXMM
    def reg_no
      13
    end

    def to_as
      "%xmm13"
    end
  end

  class OpRXMM14<OpRegXMM
    def reg_no
      14
    end

    def to_as
      "%xmm14"
    end
  end

  class OpRXMM15<OpRegXMM
    def reg_no
      15
    end

    def to_as
      "%xmm15"
    end
  end
  
  module AssemblerUtilIAModrm
    def small_integer_8bit?(num)
      num = (num & 0x7fff_ffff) - (num & 0x8000_0000)
      num.abs < 0x7f
    end

    def small_integer_32bit?(num)
      num = (num & 0x7fff_ffff_ffff_ffff) - (num & 0x8000_0000_0000_0000)
      num.abs < 0x7fff_ffff
    end

    def modrm_indirect_off32(regv, rm_reg, rm_disp)
      fstb = 0b10000000 | ((regv & 7) << 3) | (rm_reg.reg_no & 7)
      if rm_reg.is_a?(OpESP) or rm_reg.is_a?(OpRSP) then
        [[fstb, 0b00100100, rm_disp], "C2L"]
      else
        [[fstb, rm_disp], "CL"]
      end
    end

    def modrm_indirect_off8(regv, rm_reg, rm_disp)
      fstb = 0b01000000 | ((regv & 7) << 3) | (rm_reg.reg_no & 7)
      if rm_reg.is_a?(OpESP) or rm_reg.is_a?(OpRSP) then
        [[fstb, 0b00100100, rm_disp], "C3"]
      else
        [[fstb, rm_disp], "CC"]
      end
    end

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
        if rm.reg.is_a?(OpEBP) or rm.reg.is_a?(OpRBP) then
          modrm_indirect_off8(regv, rm.reg, 0)
        else
          fstb = 0b00000000 | ((regv & 7) << 3) | (rm.reg.reg_no & 7)
          if rm.reg.is_a?(OpESP) or rm.reg.is_a?(OpRSP)  then
            [[fstb, 0x24], "C2"]
          else
            [[fstb], "C"]
          end
        end
        
      when OpImmidiate8
        modrm_indirect_off8(regv, rm.reg, rm.disp.value)
        
      when OpImmidiate32
        modrm_indirect_off32(regv, rm.reg, rm.disp.value)

      when Integer
        if small_integer_8bit?(rm.disp.abs) then
          modrm_indirect_off8(regv, rm.reg, rm.disp)
        else
          modrm_indirect_off32(regv, rm.reg, rm.disp)
        end
      end
    end

    def modrm(inst, reg, rm, dst, src, src2 = nil)
      case reg
      when Integer
        case rm
        when OpRegistor
          [[0b11000000 | ((reg & 7) << 3) | (rm.reg_no & 7)], "C"]

        when OpIndirect
          modrm_indirect(reg, rm)

        when Integer, OpImmidiate
          [[0b00000000 | ((reg & 7) << 3) | 5], "C"]

        else
          return nosupported_addressing_mode(inst, dst, src, src2)
        end

      when OpRegistor
        case rm
        when OpRegistor
          [[0b11000000 | ((reg.reg_no & 7) << 3) | (rm.reg_no & 7)], "C"]

        when OpIndirect
          modrm_indirect(reg, rm)
        end

      else
        return nosupported_addressing_mode(inst, dst, src, src2)
      end
    end
  end

  module AssemblerUtilIA
    include AssemblerUtilIAModrm

    def nosupported_addressing_mode(inst, dst, src, src2 = nil)
      mess = "Not supported addessing mode in #{inst} #{dst} #{src} #{src2}"
      raise IlligalOperand, mess
    end

    def common_operand_80_imm8(dst, src, optc, inst)
      rexseq, rexfmt = rex(dst, src)
      modseq, modfmt = modrm(inst, optc, dst, dst, src)
      fmt = "#{rexfmt}C#{modfmt}C"
      (rexseq + [0x83] + modseq + [src]).pack(fmt)
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

      when OpReg32, OpReg64
        case src
        when OpImmidiate8
          common_operand_80_imm8(dst, src.value, optc, inst)

        when OpImmidiate32, Integer
          srcv = nil
          if src.is_a?(Integer)
            srcv = src
          else
            srcv = src.value
          end

          if small_integer_8bit?(srcv) then
            return common_operand_80_imm8(dst, srcv, optc, inst)
          end

          rexseq, rexfmt = rex(dst, src)

          if dst.class == OpEAX or dst.class == OpRAX then
            [*rexseq, bopc + 0x5, srcv].pack("#{rexfmt}CL")
          else
            modseq, modfmt = modrm(inst, optc, dst, dst, src)
            (rexseq + [0x81] + modseq + [srcv]).pack("#{rexfmt}C#{modfmt}L")
          end

        when OpImmidiate64
          srcv = src.value

          if small_integer_8bit?(srcv) then
            return common_operand_80_imm8(dst, srcv, optc, inst)
          end

          rexseq, rexfmt = rex(dst, src)

          if dst.class == OpEAX or dst.class == OpRAX then
            [*rexseq, bopc + 0x5, srcv].pack("#{rexfmt}CQ")
          else
            modseq, modfmt = modrm(inst, optc, dst, dst, src)
            (rexseq + [0x81] + modseq + [srcv]).pack("#{rexfmt}C#{modfmt}Q")
          end

        when OpReg32, OpReg64
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(inst, src, dst, dst, src)
          (rexseq + [bopc + 0x01] + modseq).pack("#{rexfmt}C#{modfmt}")

        when OpMem32, OpMem64
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(inst, src, dst, dst, src)
          (rexseq + [bopc + 0x03] + modseq).pack("#{rexfmt}C#{modfmt}")

        when OpIndirect
          rexseq, rexfmt = rex(src, dst)
          modseq, modfmt = modrm(inst, dst, src, dst, src)
          (rexseq + [bopc + 0x03] + modseq).pack("#{rexfmt}C#{modfmt}")

        else
          return nosupported_addressing_mode(inst, dst, src)
        end

      when OpIndirect
        case src
        when OpImmidiate8
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(inst, optc, src, dst, src)
          (rexseq + [0x83] + modseq + [src.value]).pack("#{rexfmt}C#{modfmt}")

        when OpImmidiate32, Integer
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(inst, optc, src, dst, src)
          (rexseq + [0x81] + modseq + [src.value]).pack("#{rexfmt}C#{modfmt}L")

        when OpReg32, OpReg64
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(inst, src, dst, dst, src)
          (rexseq + [bopc + 0x1] + modseq).pack("#{rexfmt}C#{modfmt}")

        else
          return nosupported_addressing_mode(inst, dst, src)
        end
      end
    end

    def common_jcc(addr, opc, lopc, inst)
      addr2 = addr
      if addr.is_a?(OpMemory) then
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

    def common_setcc(dst, opc, inst)
      case dst
      when OpReg8, OpIndirect, OpMem8
        modseq, modfmt = modrm(inst, 0, dst, dst, nil)
        ([0x0F, opc] + modseq).pack("C2#{modfmt}")
      else
        return nosupported_addressing_mode(inst, dst, nil)
      end
    end

    def common_shift(dst, optc, shftnum, inst)
      rexseq, rexfmt = rex(dst, nil)
      modseq, modfmt = modrm(inst, optc, dst, dst, shftnum)
      if shftnum.is_a?(OpImmidiate8) then
        shftnum = shftnum.value
      end

      if shftnum == 1 then
        (rexseq + [0xD1] + modseq ).pack("#{rexfmt}C#{modfmt}")
      else
        (rexseq + [0xC1] + modseq + [shftnum]).pack("#{rexfmt}C#{modfmt}C")
      end
    end

    def common_movssd(dst, src, op, inst)
      case dst
      when OpRegXMM
        case src
        when OpRegXMM
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(inst, dst, src, dst, src)
          (rexseq + [op, 0x0F, 0x10] + modseq).pack("#{rexfmt}C3#{modfmt}")

        when OpIndirect
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(inst, dst, src, dst, src)
          (rexseq + [op, 0x0F, 0x10] + modseq).pack("#{rexfmt}C3#{modfmt}")

        else
          return nosupported_addressing_mode(inst, dst, src)
        end

      when OpIndirect
        case src
        when OpRegXMM
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(inst, src, dst, dst, src)
          (rexseq + [op, 0x0F, 0x11] + modseq).pack("#{rexfmt}C3#{modfmt}")
          
        else
          return nosupported_addressing_mode(inst, dst, src)
        end

      else
        return nosupported_addressing_mode(inst, dst, src)
      end
    end

    def common_arithxmm(dst, src, op0, op1, inst)
      case dst
      when OpRegXMM
        case src
        when OpRegXMM
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(inst, dst, src, dst, src)
          if op0 then
            (rexseq + [op0, 0x0F, op1] + modseq).pack("#{rexfmt}C3#{modfmt}")
          else
            (rexseq + [0x0F, op1] + modseq).pack("#{rexfmt}C2#{modfmt}")
          end

        when OpIndirect
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(inst, dst, src, dst, src)
          if op0 then
            (rexseq + [op0, 0x0F, op1] + modseq).pack("#{rexfmt}C3#{modfmt}")
          else
            (rexseq + [0x0F, op1] + modseq).pack("#{rexfmt}C2#{modfmt}")
          end

        else
          return nosupported_addressing_mode(inst, dst, src)
        end

      else
        return nosupported_addressing_mode(inst, dst, src)
      end
    end
  end
  
  class GeneratorIABinary<Generator
    case $ruby_platform
    when /x86_64/
      include AssemblerUtilX64
    when /i.86/
      include AssemblerUtilX86
    end
    include AssemblerUtilIA

    def initialize(asm, handler = "ytl_step_handler")
      super(asm)
      @step_handler = YTLJit.address_of(handler)
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
      common_operand_80(dst, src, 0x10, 0x2, :adc)
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
        when OpImmidiate8
          [0xB0 + (dst.reg_no & 7), src.value].pack("C2")

        when Integer
          [0xB0 + (dst.reg_no & 7), src].pack("C2")
          
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
        when OpImmidiate32
          [0xB8 + (dst.reg_no & 7), src.value].pack("CL")

        when Integer
          [0xB8 + (dst.reg_no & 7), src].pack("CL")

        when OpReg32, OpReg64
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(:mov, src, dst, dst, src)
          (rexseq + [0x89] + modseq).pack("#{rexfmt}C#{modfmt}")

        when  OpIndirect
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(:mov, dst, src, dst, src)
          (rexseq + [0x8B] + modseq).pack("#{rexfmt}C#{modfmt}")
          
        else
          return nosupported_addressing_mode(:mov, dst, src)
        end
      
      when OpReg64
        case src
        when OpImmidiate32
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(:mov, 0, dst, dst, src)
          (rexseq + [0xC7] + modseq + [src.value]).pack("#{rexfmt}C#{modfmt}L")
          
        when Integer
          rexseq, rexfmt = rex(dst, src)
          if small_integer_32bit?(src) then 
            modseq, modfmt = modrm(:mov, 0, dst, dst, src)
            (rexseq + [0xC7] + modseq + [src]).pack("#{rexfmt}C#{modfmt}L")
          else
            [*rexseq, 0xB8 + (dst.reg_no & 7), src].pack("#{rexfmt}CQ")
          end

        when OpImmidiate64
          rexseq, rexfmt = rex(dst, src)
          [*rexseq,  0xB8 + (dst.reg_no & 7), src.value].pack("#{rexfmt}CQ")

        when OpReg32, OpReg64
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(:mov, src, dst, dst, src)
          (rexseq + [0x89] + modseq).pack("#{rexfmt}C#{modfmt}")

        when  OpIndirect
          rexseq, rexfmt = rex(src, dst)
          modseq, modfmt = modrm(:mov, dst, src, dst, src)
          (rexseq + [0x8B] + modseq).pack("#{rexfmt}C#{modfmt}")
          
        else
          return nosupported_addressing_mode(:mov, dst, src)
        end
      
      when OpIndirect
        case src
        when OpReg8
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(:mov, src, dst, dst, src)
          (rexseq + [0x88] + modseq).pack("#{rexfmt}C#{modfmt}")

        when OpReg32, OpReg64
          rexseq, rexfmt = rex(dst, src)
          modseq, modfmt = modrm(:mov, src, dst, dst, src)
          (rexseq + [0x89] + modseq).pack("#{rexfmt}C#{modfmt}")

        when OpImmidiate8
          rexseq, rexfmt = rex(dst, 0)
          modseq, modfmt = modrm(:mov, 0, dst, dst, src)
          (rexseq + [0xC6] + modseq + [src.value]).pack("#{rexfmt}C#{modfmt}C")

        when OpImmidiate32
          rexseq, rexfmt = rex(dst, 0)
          modseq, modfmt = modrm(:mov, 0, dst, dst, src)
          (rexseq + [0xC7] + modseq + [src.value]).pack("#{rexfmt}C#{modfmt}L")

        when Integer
          rexseq, rexfmt = rex(dst, 0)
          modseq, modfmt = modrm(:mov, 0, dst, dst, src)
          (rexseq + [0xC7] + modseq + [src]).pack("#{rexfmt}C#{modfmt}L")

        else
          return nosupported_addressing_mode(:mov, dst, src)
        end
        
      else
        return nosupported_addressing_mode(:mov, dst, src)
      end
    end

    def lea(dst, src)
      unless dst.is_a?(OpReg32) or dst.is_a?(OpReg64)
        return nosupported_addressing_mode(:lea, dst, src)
      end

      if !src.is_a?(OpIndirect)
        return nosupported_addressing_mode(:lea, dst, src)
      end

      rexseq, rexfmt = rex(src, dst)
      modseq, modfmt = modrm(:lea, dst, src, dst, src)
      (rexseq + [0x8D] + modseq).pack("#{rexfmt}C#{modfmt}")
    end

    def push(dst)
      rexseq, rexfmt = rex(dst, nil)
      case dst
      when OpReg32, OpReg64
        [*rexseq, 0x50 + (dst.reg_no & 7)].pack("#{rexfmt}C")
        
      when OpIndirect
        modseq, modfmt = modrm(:push, 6, dst, dst, nil)
        (rexseq + [0xFF] +  modseq).pack("#{rexfmt}C#{modfmt}")
        
      else
        return nosupported_addressing_mode(:push, dst, nil)
      end
    end

    def pop(dst)
      rexseq, rexfmt = rex(dst, nil)
      case dst
      when OpReg32, OpReg64
        [*rexseq, 0x58 + (dst.reg_no & 7)].pack("#{rexfmt}C")
        
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

    def seta(dst)
      common_setcc(dst, 0x97, :seta)
    end

    def setae(dst)
      common_setcc(dst, 0x93, :setae)
    end

    def setb(dst)
      common_setcc(dst, 0x92, :setb)
    end

    def setbe(dst)
      common_setcc(dst, 0x96, :setbe)
    end

    def setg(dst)
      common_setcc(dst, 0x9f, :setg)
    end

    def setge(dst)
      common_setcc(dst, 0x9d, :setge)
    end

    def setl(dst)
      common_setcc(dst, 0x9c, :setl)
    end

    def setle(dst)
      common_setcc(dst, 0x9e, :setle)
    end

    def setna(dst)
      common_setcc(dst, 0x96, :setna)
    end

    def setnae(dst)
      common_setcc(dst, 0x92, :setnae)
    end

    def setnb(dst)
      common_setcc(dst, 0x93, :setnb)
    end

    def setnbe(dst)
      common_setcc(dst, 0x97, :setnbe)
    end

    def setnc(dst)
      common_setcc(dst, 0x93, :setnc)
    end

    def setnle(dst)
      common_setcc(dst, 0x9f, :setnle)
    end

    def setno(dst)
      common_setcc(dst, 0x91, :setno)
    end

    def seto(dst)
      common_setcc(dst, 0x90, :seto)
    end

    def setz(dst)
      common_setcc(dst, 0x94, :setz)
    end

    def setnz(dst)
      common_setcc(dst, 0x95, :setnz)
    end

    def jmp(addr)
      addr2 = addr
      if addr.is_a?(OpMemory) then
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
      offset = 0
      case addr
      when Integer
        offset = addr - @asm.current_address - 5
        immidiate_call(addr, offset)      

      when OpMemory
        offset = addr.value - @asm.current_address - 5
        immidiate_call(addr, offset)      

      else
        rexseq, rexfmt = rex(addr, nil)
        modseq, modfmt = modrm(:call, 2, addr, nil, addr)
        (rexseq + [0xff] + modseq).pack("#{rexfmt}C#{modfmt}")
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
      rexseq, rexfmt = rex(dst, src)
      case dst 
      when OpReg8, OpMem8
        if src == nil then
          modseq, modfmt = modrm(:imul, 5, dst, dst, src)
          return ([0xF6] + modseq).pack("C#{modfmt}")
        end

      when OpIndirect, OpMem32
        if src == nil then
          modseq, modfmt = modrm(:imul, 5, dst, dst, src)
          return (rexseq + [0xF7] + modseq).pack("#{rexfmt}C#{modfmt}")
        end

      when OpReg32, OpReg64
        case src
        when nil
          modseq, modfmt = modrm(:imul, 5, dst, dst, src)
          return (rexseq + [0xF7] + modseq).pack("#{rexfmt}C#(modfmt}")
          
        when OpReg32, OpMem32, OpIndirect, OpReg64
          modseq, modfmt = modrm(:imul, dst, src, dst, src, src2)
          case src2 
          when nil
            return (rexseq + [0x0F, 0xAF] + modseq).pack("#{rexfmt}C2#{modfmt}")
            
          when OpImmidiate8
            fmt = "#{rexfmt}C#{modfmt}C"
            return (rexseq + [0x6B] + modseq + [src2.value]).pack(fmt)

          when OpImmidiate32
            fmt = "#{rexfmt}C#{modfmt}L"
            return (rexseq + [0x69] + modseq + [src2.value]).pack(fmt)

          when Integer
            fmt = "#{rexfmt}C#{modfmt}L"
            return (rexseq + [0x69] + modseq + [src2]).pack(fmt)
          end

        when OpImmidiate8
          modseq, modfmt = modrm(:imul, dst, dst, dst, src)
          fmt = "#{rexfmt}C#{modfmt}C"
          return (rexseq + [0x6B] + modseq + [src.value]).pack(fmt)
          
        
        when OpImmidiate32
          modseq, modfmt = modrm(:imul, dst, dst, dst, src)
          fmt = "#{rexfmt}C#{modfmt}L"
          return (rexseq + [0x69] + modseq + [src.value]).pack(fmt)

        when Integer
          modseq, modfmt = modrm(:imul, dst, dst, dst, src)
          fmt = "#{rexfmt}C#{modfmt}L"
          return (rexseq + [0x69] + modseq + [src]).pack(fmt)

        end
      end

      return nosupported_addressing_mode(:imul, dst, src, src2)
    end

    def idiv(src)
      rexseq, rexfmt = rex(src, nil)
      case src
      when OpReg8, OpMem8
        modseq, modfmt = modrm(:idiv, 7, src, src, nil)
        return ([0xF6] + modseq).pack("C#{modfmt}")

      when OpIndirect, OpMem32
        modseq, modfmt = modrm(:idiv, 7, src, src, nil)
        return (rexseq + [0xF7] + modseq).pack("#{rexfmt}C#{modfmt}")

      when OpReg32, OpReg64
        modseq, modfmt = modrm(:idiv, 7, src, src, nil)
        return (rexseq + [0xF7] + modseq).pack("#{rexfmt}C#{modfmt}")
      end

      return nosupported_addressing_mode(:idiv, src, nil, nil)
    end

    def neg(src)
      rexseq, rexfmt = rex(src, nil)
      case src
      when OpReg8, OpMem8
        modseq, modfmt = modrm(:neg, 3, src, src, nil)
        return ([0xF6] + modseq).pack("C#{modfmt}")

      when OpIndirect, OpMem32
        modseq, modfmt = modrm(:neg, 3, src, src, nil)
        return (rexseq + [0xF7] + modseq).pack("#{rexfmt}C#{modfmt}")

      when OpReg32, OpReg64
        modseq, modfmt = modrm(:neg, 3, src, src, nil)
        return (rexseq + [0xF7] + modseq).pack("#{rexfmt}C#{modfmt}")
      end

      return nosupported_addressing_mode(:neg, src, nil, nil)
    end

    def fstpl(dst)
      case dst
      when OpIndirect
        modseq, modfmt = modrm(:fstpl, 3, dst, dst, nil)
        return ([0xDD] + modseq).pack("C#{modfmt}")
      end

      return nosupported_addressing_mode(:neg, src, nil, nil)
    end

    def cdq
      [0x99].pack("C")
    end

    def movss(dst, src)
      common_movssd(dst, src, 0xF3, :movss)
    end

    def movsd(dst, src)
      common_movssd(dst, src, 0xF2, :movsd)
    end

    def addss(dst, src)
      common_arithxmm(dst, src, 0xF3, 0x58, :addss)
    end

    def addsd(dst, src)
      common_arithxmm(dst, src, 0xF2, 0x58, :addsd)
    end

    def subss(dst, src)
      common_arithxmm(dst, src, 0xF3, 0x5C, :subss)
    end

    def subsd(dst, src)
      common_arithxmm(dst, src, 0xF2, 0x5C, :subsd)
    end


    def mulss(dst, src)
      common_arithxmm(dst, src, 0xF3, 0x59, :mulss)
    end

    def mulsd(dst, src)
      common_arithxmm(dst, src, 0xF2, 0x59, :mulsd)
    end

    def divss(dst, src)
      common_arithxmm(dst, src, 0xF3, 0x5E, :divss)
    end

    def divsd(dst, src)
      common_arithxmm(dst, src, 0xF2, 0x5E, :divsd)
    end

    def comiss(dst, src)
      common_arithxmm(dst, src, nil, 0x2F, :comiss)
    end

    def comisd(dst, src)
      common_arithxmm(dst, src, 0x66, 0x2F, :comisd)
    end

    def int3
      [0xcc].pack("C")
    end
  end
end
