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
    class CollectInfoContext
      def initialize(tnode)
        @top_node = tnode
        @modified_local_var = []
        @modified_instance_var = {}
      end

      attr          :top_node
      attr          :modified_local_var
      attr          :modified_instance_var

      def merge_local_var(lvlist)
        res = nil
        lvlist.each do |lvs|
          if res then
            lvs.each_with_index do |lvt, i|
              dst = res[i]
              lvt.each do |idx, val|
                unless dst[idx].include?(val)
                  dst[idx].push val
                end
              end
            end
          else
            res = lvs.map {|lvt| lvt.dup}
          end
        end
      end
    end

    class CompileContext
      include AbsArch
      def initialize(tnode)
        @top_node = tnode
        @code_space = nil
        @assembler = nil
        
        # RETR(EAX, RAX) or RETFR(STO, XM0) or Immdiage object
        @ret_reg = RETR
        @ret_node = nil
        @depth_reg = {}
        @stack_content = []
        @reg_content = {}
      end

      attr          :top_node
      attr          :code_space
      attr          :assembler

      attr          :depth_reg
      attr_accessor :ret_reg
      attr_accessor :ret_node

      attr          :reg_content
      attr          :stack_content

      def set_reg_content(dst, val)
        if dst.is_a?(OpRegistor) then
          if val.is_a?(OpRegistor)
            @reg_content[dst] = @reg_content[val]
          else
            @reg_content[dst] = val
          end
        elsif dst.is_a?(OpIndirect) and dst.reg == SPR then
          if val.is_a?(OpRegistor)
            cpustack_setn(-dst.disp, @reg_content[val])
          else
            cpustack_setn(-dst.disp, val)
          end
        end
      end

      def cpustack_push(reg)
        @stack_content.push @reg_content[reg]
      end

      def cpustack_pop(reg)
        @reg_content[reg] = @stack_content.pop
      end

      def cpustack_setn(offset, reg)
        @reg_content[-offset] = @reg_content[reg]
      end

      def cpustack_pushn(num)
        num.times do |i|
          @stack_content.push nil
        end
      end

      def cpustack_popn(num)
        num.times do |i|
          @stack_content.pop
        end
      end

      def add_code_space(cs)
        @code_space = cs
        @assembler = Assembler.new(cs)
        @top_node.add_code_space(@code_space, cs)
      end

      def reset_using_reg
        @depth_reg = {}
      end

      def start_using_reg_aux(reg)
        if @depth_reg[reg] then
          @assembler.with_retry do
            @assembler.push(reg)
            cpustack_push(reg)
          end
        else
          @depth_reg[reg] = 0
        end
        @depth_reg[reg] += 1
      end

      def start_using_reg(reg)
        case reg
        when OpRegistor
          if reg != TMPR then
            start_using_reg_aux(reg)
          end

        when OpIndirect
          case reg.reg 
          when BPR

          else
            start_using_reg_aux(reg.reg)
          end

        when FunctionArgument
          regdst = reg.dst_opecode
          if regdst.is_a?(OpRegistor)
            start_using_reg_aux(regdst)
          end
        end
      end

      def end_using_reg_aux(reg)
        if @depth_reg[reg] then
          @depth_reg[reg] -= 1
        else
          raise "Not saved reg #{reg}"
        end
        if @depth_reg[reg] != 0 then
          @assembler.with_retry do
            @assembler.pop(reg)
            cpustack_pop(reg)
          end
        else
          @depth_reg[reg] = nil
          @reg_content.delete(reg)
        end
      end

      def end_using_reg(reg)
        case reg
        when OpRegistor
          if reg != TMPR then
            end_using_reg_aux(reg)
          end

        when OpIndirect
          case reg.reg 
          when BPR

          else
            end_using_reg_aux(reg.reg)
          end

        when FunctionArgument
          regdst = reg.dst_opecode
          if regdst.is_a?(OpRegistor) then
            end_using_reg_aux(regdst)
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
            vnode = context.ret_node
            context.start_using_reg(TMPR)
            asm.with_retry do
              asm.mov(TMPR, val)
              asm.add(TMPR, TMPR)
              asm.add(TMPR, OpImmidiate8.new(1))
            end
            context.set_reg_content(TMPR, vnode)
            context.ret_reg = TMPR
            context.ret_node = self
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
            vnode = context.ret_node
            context.start_using_reg(TMPR)
            asm.with_retry do
              asm.mov(TMPR, val)
              asm.sar(TMPR)
            end
            context.set_reg_content(TMPR, vnode)
            context.ret_node = self
            context.ret_reg = TMPR
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
              asm.mov(TMPR2, current_frame_info.offset_arg(0, TMPR2))
            end
            context.set_reg_content(TMPR2, current_frame_info)
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

=begin
        # adjust stack pointer
        casm.with_retry do
          casm.sub(SPR, rarg.size * Type::MACHINE_WORD.size)
        end
=end
        
        # make argv
        casm = context.assembler
        argbyte = rarg.size * Type::MACHINE_WORD.size
        casm.with_retry do
          casm.sub(SPR, argbyte)
        end
        context.cpustack_pushn(argbyte)

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
              casm.mov(dst, TMPR)
            end
            context.end_using_reg(context.ret_reg)
          end
          context.cpustack_setn(i, context.ret_node)
        end

        # Copy Stack Pointer
        # TMPR2 doesnt need save. Because already saved in outside
        # of send node
        context.set_reg_content(TMPR2, nil)
        casm.with_retry do
          casm.mov(TMPR2, SPR)
        end

        # stack, generate call ...
        context = yield(context, rarg)

=begin
        casm = context.assembler
        casm.with_retry do
          casm.add(SPR, rarg.size * Type::MACHINE_WORD.size)
        end
=end

        # adjust stack
        context.cpustack_popn(argbyte)
        casm.with_retry do
          casm.add(SPR, argbyte)
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
