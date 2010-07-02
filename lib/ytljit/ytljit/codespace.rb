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
    attr :refer_operands

    def reset
      @org_base_address = base_address
      self.current_pos = 0
    end

    def emit(code)
      self[self.current_pos] = code
    end

    def var_base_address(offset = 0)
      func = lambda {
        base_address + offset
      }
      ovi32 = OpVarMemAddress.new(func)
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
      # quick dirty hack to work on Cygwin & Mac OS X/Core2Duo
      # TODO: bdf and instruction set architecture should be automatically selected
      case $ruby_platform
      when /x86_64-darwin/
        objcopy_cmd = "gobjcopy -I binary -O mach-o-i386 -B i386 --adjust-vma=#{base_address} #{tmpfp.path}"
        objdump_cmd = "gobjdump -M x86-64 -D #{tmpfp.path}"

      when /x86_64/
        objcopy_cmd = "objcopy -I binary -O elf64-x86-64 -B i386 --adjust-vma=#{base_address} #{tmpfp.path}"
        objdump_cmd = "objdump -M x86-64 -D #{tmpfp.path}"

      when /i.86/
        objcopy_cmd = "objcopy -I binary -O elf32-i386 -B i386 --adjust-vma=#{base_address} #{tmpfp.path}"
        objdump_cmd = "objdump -M i386 -D #{tmpfp.path}"
      end
      system(objcopy_cmd)
      File.popen(objdump_cmd, "r") {|fp|
        fp.readlines.each do |lin|
          if /([0-9a-f]*):(\t[0-9a-f ]+? *\t.*)/ =~ lin then
            @@disasm_cache[$1] = $2
          end
        end
      }
    end

    def disassemble
      fill_disasm_cache
      @@disasm_cache.each do |add, asm|
        print "#{add}:  #{asm}\n"
      end
    end
  end
end
