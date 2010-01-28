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

  class OpVarImmidiate32<OpImmidiate32
    def initialize(var)
      @var = var
      @refer = []
    end

    def value
      @var.call
    end
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
end
