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
      @current_address = out.base_address
      @offset = 0
      @generated_code = []
      @output_stream = out
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
      @current_address += out.size
      @offset += out.size
      @generated_code.push [@offset, out]
      @output_stream.emit(out)
    end

    def method_missing(mn, *args)
      if args.any? {|e| e.is_a?(OpVarImmidiate32) } then
        valfunc = lambda {
          @generator.send(mn, *args)
        }
        offset = @offset
        stfunc = lambda {
          @output_stream[offset] = valfunc.call
        }
        args.each do |e|
          if e.is_a?(OpVarImmidiate32) then
            e.set_refer(stfunc)
          end
        end
        store_outcode(valfunc.call)
      else
        out = @generator.send(mn, *args)
        store_outcode(out)
      end
    end
  end
end
