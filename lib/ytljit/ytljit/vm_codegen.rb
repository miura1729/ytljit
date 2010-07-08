module YTLJit

=begin
  Stack layout (on stack frame)


Hi     |  |Argn                   |   |
       |  |   :                   |   |
       |  |Arg3(exception status) |   |
       |  |Arg2(block pointer)    |   |
       |  |Arg1(parent frame)     |  -+
       |  |Arg0(self)             |
       |  |Return Address         |
       +- |old bp                 | <-+
          |old bp on stack        |  -+
    EBP-> |Local Vars1            |   
          |                       |   
          |                       |   
          |Local Varsn            |   
          |Pointer to Env         |   
   SP ->  |                       |
          |                       |
LO        


  Stack layout (on heap frame)


Hi     |  |Arg0(self)             |   |
       |  |Arg1(parent frame)     |  -+
       |  |Arg2(block pointer)    |
       |  |Arg3(exception status) |
       |  |   :                   |
       |  |Arg n                  |
       |  |Return Address         |
       +- |old bp                 |  <---+
          |Pointer to Env         |  -+  |
   SP ->  |                       |   |  |
LO        |                       |   |  |
                                      |  |
                                      |  |
       +- |                       |   |  |
       |  |free func              |   |  |
       |  |mark func              |   |  |
       |  |T_DATA                 | <-+  |                                      
       |                                 |
       |                                 |
       |  |Arg n                  |      |
       |  |   :                   |      |
       |  |Arg3(exception status) |      |
       |  |Arg2(block pointer)    |      |
       |  |Arg1(parent frame)     |      |
       |  |Arg0(self)             |      |   
       |  |Not used(reserved)     |      |
       |  |Not used(reserved)     |      |
       |  |old bp on stack        | -----+
    EBP-> |Local Vars1            |   
       |  |                       |   
       |  |                       |   
       +->|Local Varsn            |   

  enter procedure
    push EBP
    SP -> EBP
    allocate frame (stack or heap)    
    Copy arguments if allocate frame on heap
    store EBP on the top of frame
    Address of top of frame -> EBP
 
  leave procedure
    Dereference of EBP -> ESP
    pop EBP
    ret

=end

  module VM
    class Context
      include AbsArch
      def initialize(tnode)
        @top_node = tnode
        @code_space = nil
        @assembler = nil
        
        # RETR(EAX, RAX) or RETFR(STO, XM0) or Immdiage object
        @ret_reg = RETR
        @used_reg = {}

        @modified_local_var = []
        @modified_instance_var = []
      end

      attr          :top_node
      attr          :code_space
      attr          :assembler

      attr_accessor :ret_reg
      attr          :used_reg
      
      attr          :modified_local_var
      attr          :modified_instance_var

      def add_code_space(cs)
        @code_space = cs
        @assembler = Assembler.new(cs)
        @top_node.add_code_space(@code_space, cs)
      end

      def reset_using_reg
        @used_reg = {}
      end

      def start_using_reg_aux(reg)
        if @used_reg[reg] then
          @assembler.with_retry do
            @assembler.push(reg)
          end
        else
          @used_reg[reg] = 0
        end
        @used_reg[reg] += 1
      end

      def start_using_reg(reg)
        case reg
        when OpRegistor
          start_using_reg_aux(reg)

        when FunctionArgument
          regdst = reg.dst_opecode
          if regdst.is_a?(OpRegistor)
            start_using_reg_aux(regdst)
          end
        end
      end

      def end_using_reg_aux(reg)
        @used_reg[reg] -= 1
        if @used_reg[reg] != 0 then
          @assembler.with_retry do
            @assembler.pop(reg)
          end
        else
          @used_reg[reg] = nil
        end
      end

      def end_using_reg(reg)
        case reg
        when OpRegistor
          end_using_reg_aux(reg)

        when FunctionArgument
          regdst = reg.dst_opecode
          if regdst.is_a?(OpRegistor)
            end_using_reg_aux(regdst)
          end
        end
      end

      def end_using_reg_only_pop(reg)
        if reg.is_a?(OpRegistor) then
          if @used_reg[reg] != 1 then
            @assembler.with_retry do
              @assembler.pop(reg)
            end
          end
        end
      end
    end

    module Node

      module UtilCodeGen
        include RubyType
        def gen_boxing(context, valnode)
          asm = context.assembler
          case valnode.type
          when :FixnumType
          else
            val = context.ret_reg
            context.start_using_reg(TMPR)
            asm.with_retry do
              asm.mov(TMPR, val)
              asm.add(TMPR, TMPR)
              asm.add(TMPR, OpImmidiate8.new(1))
              context.ret_reg = TMPR
            end
#          else
          end
          context
        end

        def gen_unboxing(context, valnode)
          asm = context.assembler
          case valnode.type
          when :FixnumType
          else
            val = context.ret_reg
            context.start_using_reg(TMPR)
            asm.with_retry do
              asm.mov(TMPR, val)
              asm.sar(TMPR)
              context.ret_reg = TMPR
            end
#          else
          end
          context
        end
      end

      module MethodTopCodeGen
        include AbsArch
        
        def gen_method_prologue(context)
          asm = context.assembler

          asm.with_retry do
            # Make linkage of frame pointer
            asm.push(BPR)
            asm.mov(BPR, SPR)
            asm.push(BPR)
            asm.mov(BPR, SPR)
          end
            
          context
        end
      end

      module MethodEndCodeGen
        include AbsArch

        def gen_method_epilogue(context)
          asm = context.assembler

          # Make linkage of frame pointer
          asm.with_retry do
            asm.mov(SPR, BPR)
            asm.pop(BPR)
            asm.mov(SPR, BPR)
            asm.pop(BPR)
          end

          context
        end
      end

      module IfNodeCodeGen
        include AbsArch
      end
      
      module LocalVarNodeCodeGen
        include AbsArch

        def gen_pursue_parent_function(context, depth)
          asm = context.assembler
          if depth != 0 then
            context.start_using_reg(TMPR2)
            asm.mov(TMPR2, BPR)
            depth.times do 
              asm.mov(TMPR2, frame_info.offset_arg(0, TMPR2))
            end
            context.ret_reg = TMPR2
          else
            context.ret_reg = BPR
          end
          context
        end
      end
    end

    module SendNodeCodeGen
      include AbsArch
      
      def gen_make_argv(context)
        casm = context.assembler
        rarg = @arguments[2..-1]

        # adjust stack pointer
        casm.with_retry do
          casm.sub(SPR, rarg.size * Type::MACHINE_WORD.size)
        end
        
        # make argv
        rarg.each_with_index do |arg, i|
          context = arg.compile(context)
          casm = context.assembler
          dst = OpIndirect.new(SPR, i * Type::MACHINE_WORD.size)
          if TMPR != context.ret_reg then
            context.start_using_reg(TMPR)
            casm.with_retry do
              casm.mov(TMPR, context.ret_reg)
              casm.mov(dst, TMPR)
            end
            context.end_using_reg(TMPR)
            context.end_using_reg(context.ret_reg)
          else
            casm.with_retry do
              casm.mov(dst, context.ret_reg)
            end
#            context.end_using_reg(context.ret_reg)
          end
        end

        # Save Stack Pointer
        context.start_using_reg(TMPR2)
        casm.with_retry do
          casm.mov(TMPR2, SPR)
        end

        # stack, generate call ...
        context = yield(context, rarg)
        context.end_using_reg(TMPR2)

        # adjust stack
        casm.with_retry do
          casm.add(SPR, rarg.size * Type::MACHINE_WORD.size)
        end

        context
      end

      def gen_call(context, fnc, numarg)
        casm = context.assembler

        callpos = nil
        casm.with_retry do 
          dmy, callpos = casm.call_with_arg(fnc, numarg)
        end

        @var_return_address = casm.output_stream.var_base_address(callpos)
        
        context
      end
    end
  end
end
