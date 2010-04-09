module YTLJit

  class StepHandler
    def step_handler(*regs)
      STDERR.print "execute: 0x#{regs[0].to_s(16)}\n"
      STDERR.print CodeSpace.disasm_cache[regs[0].to_s(16)], "\n"
      STDERR.print regs.inspect
      STDERR.print "\n"
     end
  end

  class Generator
    def initialize(asm)
      @asm = asm
    end
  end

  class OutputStream
    def asm=(a)
      @asm = a
    end

    def base_address
      0
    end

    def var_base_address
      OpVarImmidiate32.new(lambda {0})
    end
  end

  class FileOutputStream<OutputStream
    def initialize(st)
      @stream = st
    end

    def emit(code)
      @stream.write(code)
    end
  end

  class Assembler
    def initialize(out, gen = GeneratorX86Extend)
      @generator = gen.new(self)
      @output_stream = out
      @retry_mode = false
      @step_mode = false
      @step_handler = address_of("ytl_step_handler")
      reset
    end

    def reset
      @current_address = @output_stream.base_address
      @offset = 0
      @generated_code = []
    end

    attr_accessor :current_address
    attr_accessor :step_mode

    def var_current_address
      func = lambda {
        @current_address
      }
      OpVarImmidiate32.new(func)
    end

    attr_accessor :generated_code

    def store_outcode(out)
      @current_address += out.bytesize
      @offset += out.bytesize
      @generated_code.push [@offset, out]
      @output_stream.emit(out)
    end

    def with_retry(&body)
      org_base_address = @output_stream.base_address
      self.instance_eval(&body)
      while org_base_address != @output_stream.base_address do
        @retry_mode = true
        org_base_address = @output_stream.base_address
        reset
        @output_stream.reset
        self.instance_eval(&body)
        @output_stream.update_refer
      end
      @retry_mode = false
    end

    def with_current_address(address)
      org_curret_address = self.current_address
      self.current_address = address
      yield
      self.current_address = org_curret_address
    end

    def method_missing(mn, *args)
      result = nil
      if @step_mode
        out = @generator.call(@step_handler)
        store_outcode(out)
      end

      if args.any? {|e| e.is_a?(OpVarImmidiate32) } and !@retry_mode then
        offset = @offset
        stfunc = lambda {
          with_current_address(@output_stream.base_address + offset) {
            @output_stream[offset] = @generator.send(mn, *args)
          }
        }
        args.each do |e|
          if e.is_a?(OpVarImmidiate32) then
            e.add_refer(stfunc)
          end
        end
      end

      out = @generator.send(mn, *args)
      if out.is_a?(Array) then
        store_outcode(out[0])
      else
        store_outcode(out)
      end
      out
    end
  end
end
