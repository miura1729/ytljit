module YTLJit

  class Generator
    def initialize(asm)
      @asm = asm
    end
  end

  class Assembler
    def initialize(gen = GeneratorX86Binary)
      @generator = gen.new(self)
      @current_address = 0
      @outcode = ""
    end

    attr_accessor :current_address

    def flush(stream = stdojt)
      stream.write(@outcode)
    end

    def method_missing(mn, *args)
      out = @generator.send(mn, *args)
      @current_address += out.size
      @outcode += out
      out
    end
  end
end
