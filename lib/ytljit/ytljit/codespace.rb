module YTLJit
  class CodeSpace
    def initialize
      @refer_operands = []
      reset
    end
    
    def reset
      @org_base_address = base_address
      self.current_pos = 0
    end

    def emit(code)
      self[self.current_pos] = code
    end

    def var_base_address
      func = lambda {
        base_address
      }
      ovi32 = OpVarImmidiate32.new(func)
      @refer_operands.push ovi32
      ovi32
    end

    def update_refer
      @refer_operands.each do |refop|
        refop.refer.each do |stfn|
          stfn.call
        end
      end
    end
  end
end
