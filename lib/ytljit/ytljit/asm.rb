module YTLJit

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
    def initialize(out, gen = GeneratorX86Binary)
      @generator = gen.new(self)
      @output_stream = out
      @retry_mode = false
      reset
    end
    
    def reset
      @current_address = @output_stream.base_address
      @offset = 0
      @generated_code = []
    end

    attr_accessor :current_address
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

    def with_retry
      org_base_address = @output_stream.base_address
      yield
      while org_base_address != @output_stream.base_address do
        @retry_mode = true
        org_base_address = @output_stream.base_address
        reset
        @output_stream.reset
        yield
        @output_stream.update_refer
      end
      @retry_mode = false
    end

    def method_missing(mn, *args)
      if args.any? {|e| e.is_a?(OpVarImmidiate32) } then
        offset = @offset
        stfunc = lambda {
          org_curret_address = self.current_address
          self.current_address = @output_stream.base_address + offset
          @output_stream[offset] = @generator.send(mn, *args)
          self.current_address = org_curret_address
        }
        args.each do |e|
          if e.is_a?(OpVarImmidiate32) and !@retry_mode then
            e.add_refer(stfunc)
          end
        end
      end

      out = @generator.send(mn, *args)
      store_outcode(out)
    end
  end
end
