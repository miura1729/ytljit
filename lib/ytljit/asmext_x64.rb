module YTLJit
  module FuncArgX64CommonMixin
    include AbsArch
    include X64
    ARGPOS2REG = [RDI, RSI, RDX, RCX, R8, R9]
    ARGPOS2FREG = [XMM0, XMM1, XMM2, XMM3]
  end

  module FunctionArgumentX64MixinInt
    include FuncArgX64CommonMixin

    def argpos2reg
      case @abi_kind
      when :c
        ARGPOS2REG

      when :cfloat
        ARGPOS2FREG

      when :ytl
        []

      else
        raise "#{@abi_kind}"
      end
    end
  end

  module FunctionArgumentX64MixinFloat
    include FuncArgX64CommonMixin

    def argpos2reg
      case @abi_kind
      when :c
        ARGPOS2REG

      when :cfloat
        ARGPOS2FREG

      when :ytl
        []

      else
        raise "#{@abi_kind}"
      end
    end
  end

  module FunctionArgumentX64MixinCommon
    include FuncArgX64CommonMixin

    def dst_opecode
      if @no < argpos2reg.size then
        argpos2reg[@no]
      else
        spos = @no - argpos2reg.size
        OpIndirect.new(SPR, OpImmidiate8.new(spos * 8))
      end
    end

    def src_opecode
      if @no < argpos2reg.size then
        argpos2reg[@no]
      else
        # +1 means return address slot
        spos = @no - argpos2reg.size + 1
        OpIndirect.new(SPR, OpImmidiate8.new(spos * 8))
      end
    end

    def gen_access_dst(gen, inst, dst, src, src2)
      code = ""
      asm = gen.asm
      fainfo = gen.funcarg_info

      if @no == 0 then
        fainfo.area_allocate_pos.push nil
        fainfo.used_arg_tab.push Hash.new
      end

      # It can be argpos2reg.size == 0, so this "if" isn't "elsif"
      if @no == argpos2reg.size then
        offset = asm.offset
        code += asm.update_state(gen.sub(SPR, 0))
        fainfo.area_allocate_pos[-1] = offset
      end

      if @no < argpos2reg.size then
        argreg = argpos2reg[@no]

=begin        
        # for nested function call. need save previous reg.
        if asm.retry_mode != :change_op and 
            fainfo.used_arg_tab.last[@no] then
          asm.update_state(gen.push(argreg))
          fainfo.push argreg
        end
=end
        code += asm.update_state(gen.mov(argreg, src))
      else
        # spilled reg 
        spos = @no - argpos2reg.size
        argdst = OpIndirect.new(SPR, OpImmidiate8.new(spos * 8))

        if src.is_a?(OpRegXMM) then
          code += asm.update_state(gen.movsd(argdst, src))
        else
          if inst == :mov and !src.is_a?(OpRegistor) then
            code += asm.update_state(gen.send(inst, TMPR, src))
            code += asm.update_state(gen.mov(argdst, TMPR))
          else
            code += asm.update_state(gen.mov(argdst, src))
          end
        end
      end

      if asm.retry_mode != :change_op then
        # if retry mode fainfo.used_arg_tab is deleted
        fainfo.used_arg_tab.last[@no] = @size
      end
      code
    end

    # Access the passing argument from caller
    #
    def gen_access_src(gen, inst, dst, src, src2)
      asm = gen.asm
      fainfo = gen.funcarg_info
      code = ""
      if @no < argpos2reg.size then
        code += asm.update_state(gen.mov(TMPR, argpos2reg[@no]))
      else
        spos = @no - argpos2reg.size
        offset = 8 + spos * 8
        code += asm.update_state(gen.mov(TMPR, OpIndirect.new(SPR, offset)))
      end
      code += asm.update_state(gen.send(inst, src, TMPR))
      code
    end
  end

  module GeneratorExtendX64Mixin
    include FuncArgX64CommonMixin

    def mov64(dst, src)
      case dst
      when OpIndirect
        case src
        when Integer
          disp = dst.disp
          dst2 = dst.class.new(dst.reg, disp.value + 4)
          bit32val = 1 << 32
          code = mov(dst2, src / bit32val)
          code += mov(dst, src % bit32val)
          code
        else
          nosupported_addressing_mode(:mov64, dst, src)
        end
      else
        nosupported_addressing_mode(:mov64, dst, src)
      end
    end

    def call_with_arg_get_argsize(addr, argnum)
      ((argnum > 4) ? argnum : 4 )* 8
    end

    def call_with_arg(addr, argnum, argsize)
      fainfo = funcarg_info

      orgaddress = @asm.current_address
      code = ""
#      code += @asm.update_state(mov(RAX, OpImmidiate32.new(argnum)))
#      code += @asm.update_state(mov(RAX, OpImmidiate32.new(0)))
      code += @asm.update_state(call(addr))
      callpos = @asm.current_address - @asm.output_stream.base_address
      if @asm.retry_mode == :change_op then
        return [code, callpos]
      end

      # no argument this not allocate 4 words for callee working
      if argnum != 0 then
        offset = @funcarg_info.area_allocate_pos.pop
        if offset then
          imm = OpImmidiate8.new(argsize)
          code += @asm.update_state(add(SPR, imm))
          alloc_argument_area = lambda {
            @asm.with_current_address(@asm.output_stream.base_address + offset) {
              @asm.output_stream[offset] = sub(SPR, argsize)
            }
          }
          @asm.after_patch_tab.push alloc_argument_area
        end
        
        @funcarg_info.update_maxargs(argnum)
        @funcarg_info.used_arg_tab.pop
      end

      @asm.current_address = orgaddress

      [code, callpos]
    end
  end  
end
