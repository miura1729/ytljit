module YTLJit
  module AssemblerUtilX86
    def rex(dst, src)
      [[], ""]
    end

    def immidiate_call(addr, offset)
      [0xe8, offset].pack("CL")
    end
  end
end
