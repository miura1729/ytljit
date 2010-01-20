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
  end

  class FileOutputStream<OutputStream
    def initialize(st)
      @stream = st
    end

    def flush
      @stream.write(@asm.generated_code)
    end
  end

  class Assembler
    def initialize(out, gen = GeneratorX86Binary)
      out.asm = self
      @generator = gen.new(self)
      @current_address = out.base_address
      @generated_code = ""
      @output_stream = out
    end

    attr_accessor :current_address
    attr_accessor :generated_code

    def flush
      @output_stream.flush
    end

    def method_missing(mn, *args)
      out = @generator.send(mn, *args)
      @current_address += out.size
      @generated_code += out
      out
    end
  end
end
