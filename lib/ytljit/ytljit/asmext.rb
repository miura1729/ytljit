module YTLJit
  class TypedData
    def initialize(type, ent)
      @type = type
      @entity = ent
    end

    def [](arg)
      TypedData.new(@type[arg], @entity)
    end

    attr :type
    attr :entity
  end

  class GeneratorX86Extend<GeneratorX86Binary
    include X86

    def gen_access(src)
      base = src.entity
      type = src.type
      case type
      when Type::Scalar
        [mov(EAX, base), type]

      when Type::StructMember
        code = ""
        code += mov(EAX, base)
        oi = OpIndirect.new(EAX, type.offset)
        code += mov(EAX, oi)
        [code, type.type]
      end
    end

    def nosupported_addressing_mode(inst, dst, src)
      case inst
      when :mov
        if src.is_a?(TypedData) then
          rcode = ""
          rcode, rtype = gen_access(src)
          rcode += mov(dst, EAX)
          return [rcode, TypedData.new(rtype, dst)]
        end
      end

      super
    end
  end
end
