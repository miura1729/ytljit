#---------
#  Extended Specication of Assembler Level Layer
#
module YTLJit
  class TypedData
    include AbsArch

    def initialize(type, ent)
      @type = type
      @entity = ent
    end

    attr :type
    attr :entity

    def [](arg)
      TypedData.new(@type[arg], @entity)
    end

    def gen_access(gen)
      asm = gen.asm
      base = @entity
      case @type
      when Type::Scalar, Type::Pointer, Type::Array
        if base != TMPR then
          code = ""
          code += asm.update_state(gen.mov(TMPR, base))
          [code, @type]
        else
          ["", @type]
        end

      when Type::StructMember
        code = ""
        if base != TMPR then
          code += asm.update_state(gen.mov(TMPR, base))
        end
        oi = OpIndirect.new(TMPR, @type.offset)
        if @type.type.is_a?(Type::Array) then
          code += asm.update_state(gen.call_stephandler) if code != ""
          code += asm.update_state(gen.lea(TMPR, oi))
        else
          code += asm.update_state(gen.call_stephandler)  if code != ""
          code += asm.update_state(gen.mov(TMPR, oi))
        end
        [code, @type.type]

      when Type::PointedData
        # Now support only index == 0
        code = ""
        if base != TMPR then
          code += asm.update_state(gen.mov(TMPR,  base))
        end
        if @type.offset != 0 then
          oi = OpIndirect.new(TMPR, @type.offset)
          code += asm.update_state(gen.call_stephandler)  if code != ""
          code += asm.update_state(gen.lea(TMPR, oi))
        end
        ineax = OpIndirect.new(TMPR)
        code += asm.update_state(gen.call_stephandler) if code != ""
        code += asm.update_state(gen.mov(TMPR,  ineax))
        [code, @type.type]
      end
    end
  end

  class FunctionArgument
    include AbsArch

    def initialize(no)
      @no = no
    end

    def gen_access_dst(gen, inst, dst, src, src2)
      asm = gen.asm
      fainfo = gen.funcarg_info
      if @no > 0 and fainfo.used_arg_tab[@no - 1] then
        STDERR.print "Wanning - priveous argument not initialized #{caller}"
      end
      fainfo.used_arg_tab[@no] = true
      code = ""
      unless inst == :mov and src == TMPR then
        code += asm.update_state(gen.send(inst, TMPR, src))
      end
      code += asm.update_state(gen.push(TMPR))
      code
    end

    # Access the passing argument from caller
    # You can use only between entering the function and change value of
    #  stack pointer.
    #
    def gen_access_src(gen, inst, dst, src, src2)
      asm = gen.asm
      fainfo = gen.funcarg_info
      code = ""
      offset = 4 + @no * 4
      code += asm.update_state(gen.mov(TMPR, OpIndirect.new(ESP, offset)))
      code += asm.update_state(gen.send(inst, src, TMPR))
      code
    end
  end

  class FuncArgInfo
    def initialize
      @used_arg_tab = {}
    end

    attr_accessor :used_arg_tab
  end

  module GeneratorExtendMixin
    include AbsArch

    def initialize(asm)
      super
      @funcarg_info = FuncArgInfo.new
    end
    attr :funcarg_info

    def nosupported_addressing_mode(inst, dst, src, src2 = nil)
      case inst
      when :mov
        case src
        when TypedData
          orgaddress = @asm.current_address
          rcode = ""
          rcode, rtype = src.gen_access(self)
          if dst != TMPR then
            rcode += @asm.update_state(call_stephandler) if rcode != ""
            rcode += @asm.update_state(mov(dst, TMPR))
          end
          @asm.current_address = orgaddress
          return [rcode, TypedData.new(rtype, dst)]
        end
      end

      case src
      when FunctionArgument
        orgaddress = @asm.current_address
        rcode = ""
        rcode = src.gen_access_src(self, inst, dst, src, src2)
        rcode  += @asm.update_state(call_stephandler)
        @asm.current_address = orgaddress
        return rcode
      end

      case dst
      when FunctionArgument
        orgaddress = @asm.current_address
        rcode = ""
        rcode = dst.gen_access_dst(self, inst, dst, src, src2)
        rcode  += @asm.update_state(call_stephandler)
        @asm.current_address = orgaddress
        return rcode
      end

      super
    end

    def call_with_arg(addr, argnum)
      code = call(addr)
      code += add(SPR, OpImmidiate8.new(argnum * 4))
      @funcarg_info.used_arg_tab = {}
      code
    end
  end

  class GeneratorExtend<GeneratorIABinary
    include GeneratorExtendMixin
  end
end
