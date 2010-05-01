module YTLJit
  module FunctionArgumentX86Mixin
    include AbsArch

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

  module GeneratorExtendX86Mixin
    include AbsArch

    def call_with_arg(addr, argnum)
      code = call(addr)
      code += add(SPR, OpImmidiate8.new(argnum * 4))
      @funcarg_info.used_arg_tab = {}
      code
    end
  end
end  
