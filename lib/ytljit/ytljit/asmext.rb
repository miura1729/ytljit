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
      when Type::Scalar, Type::Pointer, Type::Array
        if base != EAX then
          code = ""
          code += @asm.update_state(mov(EAX, base))
          [code, type]
        else
          ["", type]
        end

      when Type::StructMember
        code = ""
        if base != EAX then
          code += @asm.update_state(mov(EAX, base))
        end
        oi = OpIndirect.new(EAX, type.offset)
        if type.type.is_a?(Type::Array) then
          code += @asm.update_state(call_stephandler) if code != ""
          code += @asm.update_state(lea(EAX, oi))
        else
          code += @asm.update_state(call_stephandler)  if code != ""
          code += @asm.update_state(mov(EAX, oi))
        end
        [code, type.type]

      when Type::PointedData
        # Now support only index == 0
        code = ""
        if base != EAX then
          code += @asm.update_state(mov(EAX,  base))
        end
        if type.offset != 0 then
          oi = OpIndirect.new(EAX, type.offset)
          code += @asm.update_state(call_stephandler)  if code != ""
          code += @asm.update_state(lea(EAX, oi))
        end
        ineax = OpIndirect.new(EAX)
        code += @asm.update_state(call_stephandler) if code != ""
        code += @asm.update_state(mov(EAX,  ineax))
        [code, type.type]
      end
    end

    def nosupported_addressing_mode(inst, dst, src, src2 = nil)
      case inst
      when :mov
        if src.is_a?(TypedData) then
          orgaddress = @asm.current_address
          rcode = ""
          rcode, rtype = gen_access(src)
          if dst != EAX then
            rcode += @asm.update_state(call_stephandler) if rcode != ""
            rcode += @asm.update_state(mov(dst, EAX))
          end
          @asm.current_address = orgaddress
          return [rcode, TypedData.new(rtype, dst)]
        end
      end

      super
    end
  end
end
