module YTLJit
  module FunctionArgumentX86Mixin
    include AbsArch

    def size
      case @kind
      when :c 
        Type::MACHINE_WORD.size

      when :ytl
        8
      end
    end

    def dst_opecode
      OpIndirect.new(SPR, OpImmidiate8.new(@no * size))
    end


    def src_opecode
      offset = 4 + @no * size
      OpIndirect.new(ESP, offset)
    end

    def gen_access_dst(gen, inst, dst, src, src2)
      argdst =  dst_opecode
      code = ""
      asm = gen.asm
      fainfo = gen.funcarg_info
      if @no == 0 then
        offset = asm.offset
        code += asm.update_state(gen.sub(SPR, fainfo.maxargs * size))
        fainfo.area_allocate_pos.push offset
      end

      fainfo.used_arg_tab[@no] = size
      unless inst == :mov and src == TMPR then
        code += asm.update_state(gen.send(inst, TMPR, src))
      end
      code += asm.update_state(gen.mov(argdst, TMPR))
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
      code += asm.update_state(gen.send(inst, src, TMPR))
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
          dst2 = dst.class.new(dst.reg, disp + 4)
          bit32val = 1 << 32
          code = @asm.update_state(mov(dst2, src / bit32val))
          code += @asm.update_state(mov(dst, src % bit32val))
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
        if @funcarg_info.used_arg_tab[i] then
          argsize += @funcarg_info.used_arg_tab[i]
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

      code += @asm.update_state(add(SPR, OpImmidiate8.new(argsize)))
      offset = @funcarg_info.area_allocate_pos.pop
      alloc_argument_area = lambda {
        asm.with_current_address(asm.output_stream.base_address + offset) {
          asm.output_stream[offset] = sub(SPR, argsize)
        }
      }
      asm.after_patch_tab.push alloc_argument_area

      @funcarg_info.update_maxargs(argnum)
      @funcarg_info.used_arg_tab = {}
      @asm.current_address = orgaddress
      
      [code, callpos]
    end
  end
end  
