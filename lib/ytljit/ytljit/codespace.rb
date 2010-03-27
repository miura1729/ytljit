module YTLJit
  class CodeSpace
    @@disasm_cache = {}
    @@disasmed_codespace = {}
    def self.disasm_cache
      @@disasm_cache
    end

    def initialize
      @refer_operands = []
      reset
    end

    attr :disasm_cache
    
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

    def fill_disasm_cache
      if @@disasmed_codespace[self] then
        return
      end
      @@disasmed_codespace[self] = true
      tmpfp = Tempfile.open("ytljitcode")
      tmpfp.write code
      tmpfp.close(false)
      system("objcopy -I binary -O elf32-i386 -B i386 --adjust-vma=#{base_address} #{tmpfp.path}")
      File.popen("objdump -D #{tmpfp.path}") {|fp|
        fp.readlines.each do |lin|
          if /([0-9a-f]*):\t[0-9a-f ]+? *\t(.*)/ =~ lin then
            @@disasm_cache[$1] = $2
          end
        end
      }
    end

    def disassemble
      fill_disasm_cache
      @@disasm_cache.each do |add, asm|
        print "#{add}:\t#{asm}\n"
      end
    end
  end
end
