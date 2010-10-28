module YTLJit
  module SSE
    XMM0 = OpRXMM0.instance
    XMM1 = OpRXMM1.instance
    XMM2 = OpRXMM2.instance
    XMM3 = OpRXMM3.instance
    XMM4 = OpRXMM4.instance
    XMM5 = OpRXMM5.instance
    XMM6 = OpRXMM6.instance
    XMM7 = OpRXMM7.instance
  end

  module SSE64
    XMM8 = OpRXMM8.instance
    XMM9 = OpRXMM9.instance
    XMM10 = OpRXMM10.instance
    XMM11 = OpRXMM11.instance
    XMM12 = OpRXMM12.instance
    XMM13 = OpRXMM13.instance
    XMM14 = OpRXMM14.instance
    XMM15 = OpRXMM15.instance
  end

  module X86
    EAX = OpEAX.instance
    EDX = OpEDX.instance
    ECX = OpECX.instance
    EBX = OpEBX.instance
    ESP = OpESP.instance
    EBP = OpEBP.instance
    ESI = OpESI.instance
    EDI = OpEDI.instance

    AL = OpAL.instance
    CL = OpCL.instance
    DL = OpDL.instance
    BL = OpBL.instance

    INDIRECT_EAX = OpIndirect.new(EAX)
    INDIRECT_EDX = OpIndirect.new(EDX)
    INDIRECT_ECX = OpIndirect.new(ECX)
    INDIRECT_EBX = OpIndirect.new(EBX)
    INDIRECT_ESP = OpIndirect.new(ESP)
    INDIRECT_EBP = OpIndirect.new(EBX)
    INDIRECT_ESI = OpIndirect.new(ESI)
    INDIRECT_EDI = OpIndirect.new(EDI)

    include SSE
  end

  module X64
    RAX = OpRAX.instance
    RDX = OpRDX.instance
    RCX = OpRCX.instance
    RBX = OpRBX.instance
    RSP = OpRSP.instance
    RBP = OpRBP.instance
    RSI = OpRSI.instance
    RDI = OpRDI.instance

    R8 = OpR8.instance
    R9 = OpR9.instance
    R10 = OpR10.instance
    R11 = OpR11.instance
    R12 = OpR12.instance
    R13 = OpR13.instance
    R14 = OpR14.instance
    R15 = OpR15.instance

    INDIRECT_RAX = OpIndirect.new(RAX)
    INDIRECT_RDX = OpIndirect.new(RDX)
    INDIRECT_RCX = OpIndirect.new(RCX)
    INDIRECT_RBX = OpIndirect.new(RBX)
    INDIRECT_RSP = OpIndirect.new(RSP)
    INDIRECT_RBP = OpIndirect.new(RBX)
    INDIRECT_RSI = OpIndirect.new(RSI)
    INDIRECT_RDI = OpIndirect.new(RDI)

    include SSE
    include SSE64
  end

  module AbsArch
    AL = OpAL.instance
    CL = OpCL.instance
    DL = OpDL.instance
    BL = OpBL.instance

    include SSE
    case $ruby_platform
    when /i.86/
      TMPR = OpEAX.instance
      TMPR2 = OpEDX.instance
      TMPR3 = OpECX.instance
      DBLLOR = OpEAX.instance
      DBLHIR = OpEDX.instance
      RETR = OpEAX.instance
      SPR = OpESP.instance
      BPR = OpEBP.instance
    when /x86_64/
      TMPR = OpRAX.instance
#      TMPR2 = OpRDX.instance
#      TMPR3 = OpRCX.instance
      TMPR2 = OpR10.instance
      TMPR3 = OpR11.instance
      DBLLOR = OpRAX.instance
      DBLHIR = OpRDX.instance
      RETR = OpRAX.instance
      SPR = OpRSP.instance
      BPR = OpRBP.instance
    end
    INDIRECT_TMPR = OpIndirect.new(TMPR)
    INDIRECT_TMPR2 = OpIndirect.new(TMPR2)
    INDIRECT_RETR = OpIndirect.new(RETR)
    INDIRECT_SPR = OpIndirect.new(SPR)
    INDIRECT_BPR = OpIndirect.new(BPR)
    FUNC_ARG = Hash.new {|hash, key| 
      hash[key] = FunctionArgumentInt.new(key, :c)
    }
    FUNC_FLOAT_ARG = Hash.new {|hash, key| 
      hash[key] = FunctionArgumentFloat.new(key, :cfloat)
    }
    FUNC_ARG_YTL = Hash.new {|hash, key| 
      hash[key] = FunctionArgumentInt.new(key, :ytl)
    }
    FUNC_FLOAT_ARG_YTL = Hash.new {|hash, key| 
      hash[key] = FunctionArgumentFloat.new(key, :ytl)
    }
  end

  module InternalRubyType
    include AbsArch
    VALUE = AsmType::MACHINE_WORD
    P_CHAR = AsmType::Pointer.new(AsmType::INT8)

    RBasic = AsmType::Struct.new(
              VALUE, :flags,
              VALUE, :klass
             )
    RString = AsmType::Struct.new(
               RBasic, :basic,
               AsmType::Union.new(
                AsmType::Struct.new(
                 AsmType::INT32, :len,
                 P_CHAR, :ptr,
                 AsmType::Union.new(
                   AsmType::INT32, :capa,
                   VALUE, :shared,
                 ), :aux
                ), :heap,
                AsmType::Array.new(
                   AsmType::INT8,
                   24
                ), :ary
               ), :as
              )

    RFloat = AsmType::Struct.new(
               RBasic, :basic,
               AsmType::DOUBLE, :float_value
              )

    EMBEDER_FLAG = (1 << 13)
    def self.rstring_ptr(str, csstart, cscont)
      cs_embed = CodeSpace.new

      asm = Assembler.new(csstart)
      rsstr = TypedData.new(InternalRubyType::RString, str)
      # asm.step_mode = true
      asm.with_retry do
        asm.mov(TMPR, rsstr[:basic][:flags])
        asm.and(TMPR, EMBEDER_FLAG)
        asm.jz(cs_embed.var_base_address)
        asm.mov(TMPR, rsstr[:as][:heap][:ptr])
        asm.jmp(cscont.var_base_address)
      end

      asm = Assembler.new(cs_embed)
      # asm.step_mode = true
      asm.with_retry do
        asm.mov(TMPR, rsstr[:as][:ary])
        asm.jmp(cscont.var_base_address)
      end
    end
  end
end
