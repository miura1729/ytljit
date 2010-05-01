module YTLJit
  module AssemblerUtilX64
    def rex(dst, src)
      rrex = 0
      if dst.is_a?(OpReg64) then
        rrex |= 0b1000
        if dst.reg_no > 8 then
          rrex |= 0b100
        end
      end

      if dst.is_a?(OpReg64) then
        rrex |= 0b1000
        if dst.reg_no > 8 then
          rrex |= 0b100
        end
      end

      if src.is_a?(OpImmidiate64) then
        rrex |= 0b1000
      end

      if rrex != 0 then
        [[0x40 + rrex], "C"]
      else
        [[], ""]
      end
    end
  end
end
