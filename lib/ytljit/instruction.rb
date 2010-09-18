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

    def to_as
      "$0x#{value.to_s(16)}"
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

  module OpVarValueMixin
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

    def to_immidiate(klass = OpVarImmidiateAddress)
      klass.new(@var)
    end
  end

  class OpVarImmidiate32<OpImmidiate32
    include OpVarValueMixin
  end

  class OpVarImmidiate64<OpImmidiate64
    include OpVarValueMixin
  end

  class OpMemory<Operand
    def initialize(address)
      @value = address
    end

    def address
      @value
    end

    attr :value

    def to_as
      "#{value.to_s(16)}"
    end
  end

  class OpMem8<OpMemory
  end

  class OpMem16<OpMemory
  end

  class OpMem32<OpMemory
  end

  class OpVarMem32<OpMem32
    include OpVarValueMixin
  end

  class OpMem64<OpMemory
  end

  class OpVarMem64<OpMem64
    include OpVarValueMixin
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


    def to_as
      "#{@disp}(#{@reg.to_as})"
    end
  end

  case $ruby_platform
  when /x86_64/
    class OpVarImmidiateAddress<OpVarImmidiate64; end
    class OpImmidiateAddress<OpImmidiate64; end
    class OpImmidiateMachineWord<OpImmidiate64; end
    class OpVarMemAddress<OpVarMem64; end
    class OpMemAddress<OpMem64; end
  when /i.86/
    class OpVarImmidiateAddress<OpVarImmidiate32; end
    class OpImmidiateAddress<OpImmidiate32; end
    class OpImmidiateMachineWord<OpImmidiate32; end
    class OpVarMemAddress<OpVarMem32; end
    class OpMemAddress<OpMem32; end
  end
end
