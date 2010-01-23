module YTLJit
  class CodeSpace
    def initialize
      @asm = nil
    end

    attr_accessor :asm

    def flush
      self[self.current_pos] = @asm.generated_code
    end

    def emit(code)
      self[self.current_pos] = code
    end
  end
end
