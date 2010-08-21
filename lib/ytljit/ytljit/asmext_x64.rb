module YTLJit
  module FuncArgX64CommonMixin
    include AbsArch
    include X64
    ARGPOS2REG = [RDI, RSI, RDX, RCX, R8, R9]
  end

  module FunctionArgumentX64Mixin
    include FuncArgX64CommonMixin

    def argpos2reg
      case @kind
      when :c
        ARGPOS2REG

      when :ytl
        []

      else
        raise "#{@kind}"
      end
    end

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
        spos = @no - argpos2reg.size
        OpIndirect.new(SPR, OpImmidiate8.new(spos * 8))
      end
    end

    def gen_access_dst(gen, inst, dst, src, src2)
      code = ""
      asm = gen.asm
      fainfo = gen.funcarg_info

      if @no == 0 then
        fainfo.area_allocate_pos.push nil
      end

      # It can be argpos2reg.size == 0, so this "if" isn't "elsif"
      if @no == argpos2reg.size then
        offset = asm.offset
        code += asm.update_state(gen.sub(SPR, 0))
        fainfo.area_allocate_pos[-1] = offset
      end

      if @no < argpos2reg.size then
        argreg = argpos2reg[@no]
        
        # for nested function call. need save previous reg.
        if fainfo.used_arg_tab[@no] then
          asm.update_state(gen.push(argreg))
          fainfo.push argreg
        end
        code += asm.update_state(gen.mov(argreg, src))
      else
        # spilled reg 
        spos = @no - argpos2reg.size
        argdst = OpIndirect.new(SPR, OpImmidiate8.new(spos * 8))

        unless inst == :mov and src == TMPR then
          code += asm.update_state(gen.send(inst, TMPR, src))
        end
        code += asm.update_state(gen.mov(argdst, TMPR))
      end

      fainfo.used_arg_tab[@no] = @size
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
      src2 = OpImmidiate64.new(src)
      @asm.update_state(mov(dst, src2))
    end

    def call_with_arg_get_argsize(addr, argnum)
      argnum * 8
    end

    def call_with_arg(addr, argnum, argsize)
      fainfo = funcarg_info

      orgaddress = @asm.current_address
      code = ""
      code += @asm.update_state(mov(RAX, OpImmidiate32.new(argnum)))
      code += @asm.update_state(call(addr))
      callpos = @asm.current_address - @asm.output_stream.base_address

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
      @funcarg_info.used_arg_tab = {}

=begin
      # Save already stored restorer
      uat = @funcarg_info.used_arg_tab
      while !fainfo.empty? do
        nreg = fainfo.pop
        if argpos = ARGPOS2REG.index(nreg) then
          if uat[argpos] then
            fainfo.push nreg
            break
          else
            code += @asm.update_state(pop(nreg))
            uat[argpos] = true
          end
        else
          fainfo.push nreg
          break
        end
      end
=end

      @asm.current_address = orgaddress

      [code, callpos]
    end
  end  
end
