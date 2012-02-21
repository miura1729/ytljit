module YTLJit
  module FunctionArgumentX86Mixin
    include AbsArch

    def size
      case @abi_kind
      when :c 
        AsmType::MACHINE_WORD.size

      when :ytl, :cfloat
        8
      end
    end

    def dst_opecode
      OpIndirect.new(SPR, OpImmidiate8.new(@no * size))
    end


    def src_opecode
      # AsmType::MACHINE_WORD.size is return address slot
      offset = AsmType::MACHINE_WORD.size + @no * size
      OpIndirect.new(SPR, offset)
    end

    def gen_access_dst(gen, inst, dst, src, src2)
      argdst =  dst_opecode
      code = ""
      asm = gen.asm
      fainfo = gen.funcarg_info
      if @no == 0 then
        offset = asm.offset
        if fainfo.maxargs  > 16 then
          allocsiz = OpImmidiate32.new(fainfo.maxargs * size)
        else
          allocsiz = OpImmidiate8.new(fainfo.maxargs * size)
        end
        code += asm.update_state(gen.sub(SPR, allocsiz))
        fainfo.area_allocate_pos.push offset
        fainfo.used_arg_tab.push Hash.new
      end

      if asm.retry_mode != :change_op then
        # if retry mode fainfo.used_arg_tab is deleted
        fainfo.used_arg_tab.last[@no] = size
      end
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
      code += asm.update_state(gen.mov(TMPR, src_opecode))
      code += asm.update_state(gen.send(inst, dst, TMPR))
      code
    end
  end

  module GeneratorExtendX86Mixin
    include AbsArch

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
      argsize = 0
      argnum.times do |i| 
        if @funcarg_info.used_arg_tab.last[i] then
          argsize += @funcarg_info.used_arg_tab.last[i]
        else
          STDERR.print "Wanrnning arg not initialized -- #{i}\n"
          argsize += 4
        end
      end
      argsize
    end

    def call_with_arg(addr, argnum, argsize)
      orgaddress = @asm.current_address
      code = @asm.update_state(call(addr))
      callpos = @asm.current_address - @asm.output_stream.base_address
      if @asm.retry_mode == :change_op then
        return [code, callpos]
      end
      
      if argnum != 0 then
        code += @asm.update_state(add(SPR, OpImmidiate8.new(argsize)))
        offset = @funcarg_info.area_allocate_pos.pop
        if @funcarg_info.maxargs > 16 then
          allocsiz = OpImmidiate32.new(argsize)
        else
          allocsiz = OpImmidiate8.new(argsize)
        end
        alloc_argument_area = lambda {
          asm.with_current_address(asm.output_stream.base_address + offset) {
            asm.output_stream[offset] = sub(SPR, allocsiz)
          }
        }
        asm.after_patch_tab.push alloc_argument_area
        
        @funcarg_info.update_maxargs(argnum)
        @funcarg_info.used_arg_tab.pop
      end
      @asm.current_address = orgaddress
      
      [code, callpos]
    end
  end
end  
