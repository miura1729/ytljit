module YTLJit
  class CodeSpace
    def emit(code)
      self[self.current_pos] = code
    end
  end
end
