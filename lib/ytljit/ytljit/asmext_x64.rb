module YTLJit
  module FunctionArgumentX64Mixin
    include X64

    ARGPOS2REG = [RDI, RSI, RDX, RCX, R8, R9]
    def gen_access_dst(gen, inst, dst, src, src2)
      asm = gen.asm
      fainfo = gen.funcarg_info
      fainfo.used_arg_tab[@no] = true
      code = ""
      if @no < ARGPOS2REG.size then
        code += asm.update_state(gen.mov(ARGPOS2REG[@no], src))
      end
      code
    end

    # Access the passing argument from caller
    #
    def gen_access_src(gen, inst, dst, src, src2)
      asm = gen.asm
      fainfo = gen.funcarg_info
      code = ""
      if @no < ARGPOS2REG.size then
        code += asm.update_state(gen.mov(RAX, ARGPOS2REG[@no]))
      end
      code += asm.update_state(gen.send(inst, src, RAX))
      code
    end
  end

  module GeneratorExtendX64Mixin
    include X64
    def call_with_arg(addr, argnum)
      code = ""
      code += mov(RAX, OpImmidiate32.new(argnum))
      code += call(addr)
      @funcarg_info.used_arg_tab = {}
      code
    end
  end
end  
