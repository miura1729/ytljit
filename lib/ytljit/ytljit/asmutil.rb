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

  module RubyType
    VALUE = Type::INT32
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
      
      rshello = TypedData.new(RubyType::RString, str)
      # asm.step_mode = true
      asm.with_retry do
        asm.mov(X86::EAX, rshello[:basic][:flags])
        asm.and(X86::EAX, EMBEDER_FLAG)
        asm.jz(cs_embed.var_base_address)
        asm.mov(X86::EAX, rshello[:as][:heap][:ptr])
        asm.jmp(cscont.var_base_address)
      end
      asm = Assembler.new(cs_embed)
      # asm.step_mode = true
      asm.with_retry do
        asm.mov(X86::EAX, rshello[:as][:ary])
        asm.jmp(cscont.var_base_address)
      end
    end
  end
end
