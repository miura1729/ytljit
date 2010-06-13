module YTLJit
  module FunctionArgumentX86Mixin
    include AbsArch
    ArgumentAddress = []

    def gen_access_dst(gen, inst, dst, src, src2)
      unless ArgumentAddress[@no] then
        ArgumentAddress[@no] = OpIndirect.new(SPR, OpImmidiate8.new(@no * 4))
      end
      code = ""
      asm = gen.asm
      fainfo = gen.funcarg_info
      if @no == 0 then
        offset = asm.offset
        code += asm.update_state(gen.sub(SPR, fainfo.maxargs * 4))
        fainfo.area_allocate_pos.push offset
      end

      if @no > 0 and fainfo.used_arg_tab[@no - 1] then
#        STDERR.print "Wanning - priveous argument not initialized #{caller}\n"
        STDERR.print "Wanning - priveous argument not initialized \n"
      end
      fainfo.used_arg_tab[@no] = true
      unless inst == :mov and src == TMPR then
        code += asm.update_state(gen.send(inst, TMPR, src))
      end
      code += asm.update_state(gen.mov(ArgumentAddress[@no], TMPR))
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

  module GeneratorExtendX86Mixin
    include AbsArch

    def call_with_arg(addr, argnum)
      orgaddress = @asm.current_address
      code = @asm.update_state(call(addr))

      code += @asm.update_state(add(SPR, OpImmidiate8.new(argnum * 4)))
      offset = @funcarg_info.area_allocate_pos.pop
      alloc_argument_area = lambda {
        asm.with_current_address(asm.output_stream.base_address + offset) {
          asm.output_stream[offset] = sub(SPR, argnum * 4)
        }
      }
      asm.after_patch_tab.push alloc_argument_area

      @funcarg_info.update_maxargs(argnum)
      @funcarg_info.used_arg_tab = {}
      @asm.current_address = orgaddress
      code
    end
  end
end  
