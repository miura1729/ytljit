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

  module OpVarImmidiateMixin
    def initialize(var)
      @var = var
      @refer = []
    end

    def refer
      @refer
    end

    def value
      @var.call
    end

    def add_refer(stfunc)
      @refer.push stfunc
    end
  end

  class OpVarImmidiate32<OpImmidiate32
    include OpVarImmidiateMixin
  end

  class OpVarImmidiate64<OpImmidiate64
    include OpVarImmidiateMixin
  end

  case $ruby_platform
  when /x86_64/
    class OpVarImmidiateAddress<OpVarImmidiate64; end
  when /i.86/
    class OpVarImmidiateAddress<OpVarImmidiate32; end
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
