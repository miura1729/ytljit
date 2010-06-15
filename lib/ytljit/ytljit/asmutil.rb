module YTLJit
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
  end

  module AbsArch
    case $ruby_platform
    when /i.86/
      TMPR = OpEAX.instance
      TMPR2 = OpEDX.instance
      TMPR3 = OpECX.instance
      RETR = OpEAX.instance
      SPR = OpESP.instance
      BPR = OpEBP.instance
    when /x86_64/
      TMPR = OpRAX.instance
      TMPR2 = OpR10.instance
      TMPR3 = OpR11.instance
      RETR = OpRAX.instance
      SPR = OpRSP.instance
      BPR = OpRBP.instance
    end
    INDIRECT_TMPR = OpIndirect.new(TMPR)
    INDIRECT_TMPR2 = OpIndirect.new(TMPR2)
    INDIRECT_RETR = OpIndirect.new(RETR)
    INDIRECT_SPR = OpIndirect.new(SPR)
    INDIRECT_BPR = OpIndirect.new(BPR)
    FUNC_ARG = Hash.new {|hash, key| hash[key] = FunctionArgument.new(key, 4)}
    FUNC_ARG64 = Hash.new {|hash, key| hash[key] = FunctionArgument.new(key, 8)}
  end

  module RubyType
    include AbsArch
    VALUE = Type::MACHINE_WORD
    P_CHAR = Type::Pointer.new(Type::INT8)

    RBasic = Type::Struct.new(
              VALUE, :flags,
              VALUE, :klass
             )
    RString = Type::Struct.new(
               RBasic, :basic,
               Type::Union.new(
                Type::Struct.new(
                 Type::INT32, :len,
                 P_CHAR, :ptr,
                 Type::Union.new(
                   Type::INT32, :capa,
                   VALUE, :shared,
                 ), :aux
                ), :heap,
                Type::Array.new(
                   Type::INT8,
                   24
                ), :ary
               ), :as
              )

    EMBEDER_FLAG = (1 << 13)
    def self.rstring_ptr(str, csstart, cscont)
      cs_embed = CodeSpace.new

      asm = Assembler.new(csstart)
      rsstr = TypedData.new(RubyType::RString, str)
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
