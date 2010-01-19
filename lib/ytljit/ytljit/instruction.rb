#
# 
#
require 'singleton'

module YTLJit

  class Operand
  end

  class OpImmidiate<Operand
    def initialize(value)
      @value = value
    end

    attr :value
  end

  class OpImmidiate8<OpImmidiate
  end

  class OpImmidiate16<OpImmidiate
  end

  class OpImmidiate32<OpImmidiate
  end

  class OpImmidiate64<OpImmidiate
  end

  class OpMemory<Operand
    def initialize(address)
      @value = address
    end

    def address
      @value
    end

    attr :value
  end

  class OpMem8<OpMemory
  end

  class OpMem16<OpMemory
  end

  class OpMem32<OpMemory
  end

  class OpMem64<OpMemory
  end

  class OpRegistor<Operand
    include Singleton
    def value
      reg_no
    end
  end

  class OpIndirect<Operand
    def initialize(reg, disp = 0)
      @reg = reg
      @disp = disp
    end

    attr :reg
    attr :disp
  end

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

    def flush
      p @outcode
    end

    def method_missing(mn, *args)
      out = @generator.send(mn, *args)
      @current_address += out.size
      @outcode += out
      out
    end
  end
end
