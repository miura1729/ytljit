module YTLJit
  module FuncArgX64CommonMixin
    include X64
    ARGPOS2REG = [RDI, RSI, RDX, RCX, R8, R9]
  end

  module FunctionArgumentX64Mixin
    include FuncArgX64CommonMixin
    ArgumentAddress = []

    def gen_access_dst(gen, inst, dst, src, src2)
      if @no >= ARGPOS2REG.size and ArgumentAddress[@no] == nil then
        spos = @no - ARGPOS2REG.size
        ArgumentAddress[@no] = OpIndirect.new(SPR, OpImmidiate8.new(spos * 8))
      end
      code = ""
      asm = gen.asm
      fainfo = gen.funcarg_info
      if @no == ARGPOS2REG.size then
        offset = asm.offset
        code += asm.update_state(gen.sub(RSP, fainfo.maxargs * 8))
        fainfo.area_allocate_pos.push offset
      end

      if @no < ARGPOS2REG.size then
        argreg = ARGPOS2REG[@no]
        
        # for nested function call. need save previous reg.
        if fainfo.used_arg_tab[@no] then
          asm.update_state(gen.push(argreg))
          fainfo.push argreg
        end
        code += asm.update_state(gen.mov(argreg, src))
      else
        # spilled reg 
        unless inst == :mov and src == RAX then
          code += asm.update_state(gen.send(inst, RAX, src))
        end
        code += asm.update_state(gen.push(RAX))
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
      if @no < ARGPOS2REG.size then
        code += asm.update_state(gen.mov(RAX, ARGPOS2REG[@no]))
      end
      code += asm.update_state(gen.send(inst, src, RAX))
      code
    end
  end

  module GeneratorExtendX64Mixin
    include FuncArgX64CommonMixin

    def call_with_arg(addr, argnum)
      fainfo = funcarg_info

      orgaddress = @asm.current_address
      code = ""
      code += @asm.update_state(mov(RAX, OpImmidiate32.new(argnum)))
      code += @asm.update_state(call(addr))

      if argnum > ARGPOS2REG.size then
        imm = OpImmidiate8.new((argnum - ARGPOS2REG.size) * 8)
        code += @asm.update_state(add(SPR, imm))
        offset = @funcarg_info.area_allocate_pos.pop
        alloc_argument_area = lambda {
          asm.with_current_address(asm.output_stream.base_address + offset) {
            asm.output_stream[offset] = gen.sub(RSP, fainfo.maxargs * 8)
          }
        }
        asm.after_patch_tab.push alloc_argument_area
      end

      @funcarg_info.update_maxargs(argnum)
      @funcarg_info.used_arg_tab = {}
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

      @asm.current_address = orgaddress
      code
    end
  end  
end
