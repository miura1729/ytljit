module YTLJit
  module AssemblerUtilX64
    def rex(dst, src)
      rrex = 0
      if dst.is_a?(OpReg64) then
        rrex |= 0b1000
        if dst.reg_no >= 8 then
          rrex |= 0b1
        end
      end
      
      if dst.is_a?(OpIndirect) and dst.reg.is_a?(OpReg64) then
        if dst.reg_no >= 8 then
          rrex |= 0b1000
          rrex |= 0b1
        end
      end
      
      if src.is_a?(OpReg64) then
        rrex |= 0b1000
        if src.reg_no >= 8 then
          rrex |= 0b100
        end
      end

      if src.is_a?(OpIndirect) and src.reg.is_a?(OpReg64) then
        if dst.reg_no >= 8 then
          rrex |= 0b1000
          rrex |= 0b1
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

    def immidiate_call(addr, offset)
      if offset.abs > 0x7fff_ffff then
        addrent = @asm.add_value_entry(addr)
        offset = addrent.value - @asm.current_address - 7
        modseq, modfmt = modrm(:call, 2, offset, nil, addr)
        [0x48, 0xff, *modseq, offset].pack("CC#{modfmt}L")
      else
        [0xe8, offset].pack("CL")
      end
    end
  end
end
