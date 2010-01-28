module YTLJit
  class CodeSpace
    def initialize
      @org_base_address = base_address
      @export = []
    end

    def emit(code)
      self[self.current_pos] = code
    end

    def var_base_address
      func = lambda {
        base_address
      }
      ovi32 = OpVarImmidiate32.new(func)
      @export.push ovi32
      ovi32
    end
  end
end
