module YTLJit

  class StepHandler
    REG_NAME = ["EAX", "ECX", "EDX", "EBX", "EBP", "ESP", "EDI"]
    def step_handler(*regs)
      STDERR.print "#{regs[0].to_s(16)} "
      STDERR.print CodeSpace.disasm_cache[regs[0].to_s(16)], "\n"
      regs.each_with_index do |val, i|
        STDERR.print REG_NAME[i]
        STDERR.print ": 0x"
        STDERR.print val.to_s(16)
        STDERR.print " "
      end
      STDERR.print "\n"
     end
  end

  class Generator
    def initialize(asm)
      @asm = asm
    end
    attr :asm
  end

  class OutputStream
    def asm=(a)
      @asm = a
    end

    def base_address
      0
    end

    def var_base_address(offset = 0)
      OpVarMemAddress.new(lambda {offset})
    end
  end

  class FileOutputStream<OutputStream
    def initialize(st)
      @stream = st
    end

    def emit(code)
      @stream.write(code)
    end
  end

  class DummyOutputStream<OutputStream
    def initialize(st)
    end

    def emit(code)
    end
  end

  class Assembler
    @@value_table_cache = {}
    @@value_table_entity = ValueSpace.new

    def self.set_value_table(out)
      @@value_table_cache = {}
      @@value_table_entity = out
    end

    def self.get_value_table(out)
      [@@value_table_entity, @@value_table_cache]
    end

    def initialize(out, gen = GeneratorExtend)
      @generator = gen.new(self)
      @output_stream = out
      @retry_mode = false
      @step_mode = false
      @asmsend_history = []

      # Instruction pach table for forwarding reference
      # This is array of proc object.
      @after_patch_tab = []
      reset
    end

    def reset
      @current_address = @output_stream.base_address
      @offset = 0
    end

    attr_accessor :current_address
    attr_accessor :step_mode
    attr          :offset
    attr          :output_stream
    attr          :after_patch_tab

    def var_current_address
      func = lambda {
        @current_address
      }
      OpVarMemAddress.new(func)
    end

    attr_accessor :generated_code

    def store_outcode(out)
      update_state(out)
      @offset += out.bytesize
      @output_stream.emit(out)
      out
    end

    def update_state(out)
      @current_address += out.bytesize
      out
    end

    def with_retry(&body)
      org_base_address = @output_stream.base_address
      yield

      @retry_mode = true
      while org_base_address != @output_stream.base_address do
        org_base_address = @output_stream.base_address
        reset
        @output_stream.reset
        @asmsend_history.each do |arg|
          send(arg[0], *arg[1])
        end
        @output_stream.update_refer
      end

      @after_patch_tab.each do |patproc|
        patproc.call
      end
      @retry_mode = false
    end

    def add_value_entry(val)
      off= nil
      unless off = @@value_table_cache[val] then
        off = @@value_table_entity.current_pos
        @@value_table_entity.emit([val.value].pack("Q"))
        @@value_table_cache[val] = off
      end

      @@value_table_entity.var_base_address(off)
    end

    def add_var_value_retry_func(mn, args)
      if args.any? {|e| e.is_a?(OpVarValueMixin) } and 
         !@retry_mode then
        offset = @offset
        stfunc = lambda {
          with_current_address(@output_stream.base_address + offset) {
            out = @generator.send(mn, *args)
            if out.is_a?(Array)
              @output_stream[offset] = out[0]
            else
              @output_stream[offset] = out
            end
          }
        }
        args.each do |e|
          if e.is_a?(OpVarValueMixin) then
            e.add_refer(stfunc)
          end
        end
      end
    end

    def method_missing(mn, *args)
      out = @generator.call_stephandler
      store_outcode(out)

      if @retry_mode == false then
        @asmsend_history.push [mn, args]
      end
        
      add_var_value_retry_func(mn, args)
      out = @generator.send(mn, *args)
      if out.is_a?(Array) then
        store_outcode(out[0])
      else
        store_outcode(out)
      end
      out
    end

    def with_current_address(address)
      org_curret_address = self.current_address
      self.current_address = address
      yield
      self.current_address = org_curret_address
    end
  end
end
