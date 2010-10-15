module YTLJit

=begin
  Stack layout (on stack frame)


Hi     |  |Argn                   |   |
       |  |   :                   |   |
       |  |Arg2(self)             |   |
       |  |Arg1(block pointer)    |   |
       |  |Arg0(parent frame)     |  -+
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

                                      |
Hi     |  |Arg0(parent frame)     |  -+
       |  |Arg1(block pointer)    |  
       |  |Arg2(self)             |
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
        @yield_node = []
      end

      attr          :top_node
      attr          :modified_local_var
      attr_accessor :modified_instance_var
      attr_accessor :yield_node

      def merge_local_var(lvlist)
        res = nil
        lvlist.each do |lvs|
          if res then
            lvs.each_with_index do |lvt, i|
              dst = res[i]
              lvt.each do |idx, vall|
                dst[idx] = dst[idx] | vall
              end
            end
          else
            res = lvs.map {|lvt| lvt.dup}
          end
        end

        @modified_local_var = res
      end

      def merge_instance_var(lvlist)
        res = nil
        lvlist.each do |lvs|
          if res then
            lvs.each do |name, vall|
              res[name] = res[name] | vall
            end
          else
            res = lvs.dup
          end
        end
      
        @modified_instance_var = res
      end
    end
    
    class TypeInferenceContext
      def initialize(tnode)
        @top_node = tnode
        @current_method_signature_node = []
        @convergent = false
      end

      def to_key(offset = -1)
        cursig = @current_method_signature_node[offset]
        res = cursig.map { |enode|
          if enode.is_a?(Node::BaseNode) then
            enode.decide_type_once(to_key(offset - 1))
            enode.type
          else
            enode
          end
        }
        res
      end

      attr          :top_node
      attr          :current_method_signature_node
      attr_accessor :convergent
    end

    class CompileContext
      include AbsArch
      def initialize(tnode)
        @top_node = tnode
        @code_space = nil

        # Signature of current compiling method
        # It is array, because method may be nest.
        @current_method_signature = []
        
        # RETR(EAX, RAX) or RETFR(STO, XM0) or Immdiage object
        @ret_reg = RETR
        @ret_node = nil
        @depth_reg = {}
        @stack_content = []
        @reg_content = {}

        # Use only type inference compile mode
        @slf = nil
      end

      attr          :top_node
      attr          :code_space

      attr          :current_method_signature

      attr          :depth_reg
      attr_accessor :ret_reg
      attr_accessor :ret_node

      attr          :reg_content
      attr          :stack_content

      attr_accessor :slf

      def set_reg_content(dst, val)
        if dst.is_a?(FunctionArgument) then
          dst = dst.dst_opecode
        end
        if dst.is_a?(OpRegistor) then
          if val.is_a?(OpRegistor)
            @reg_content[dst] = @reg_content[val]
          else
            @reg_content[dst] = val
          end
        elsif dst.is_a?(OpIndirect) and dst.reg == SPR then
          wsiz = AsmType::MACHINE_WORD.size
          if val.is_a?(OpRegistor)
            cpustack_setn(dst.disp.value / wsiz, @reg_content[val])
          else
            cpustack_setn(dst.disp.value / wsiz, val)
          end
        else
          p "foo"
          p dst
        end
      end

      def cpustack_push(reg)
        @stack_content.push @reg_content[reg]
      end

      def cpustack_pop(reg)
        @reg_content[reg] = @stack_content.pop
      end

      def cpustack_setn(offset, val)
        @stack_content[-offset] = val
      end

      def cpustack_pushn(num)
        wsiz = AsmType::MACHINE_WORD.size
        (num / wsiz).times do |i|
          @stack_content.push 1.2
        end
      end

      def cpustack_popn(num)
        wsiz = AsmType::MACHINE_WORD.size
        (num / wsiz).times do |i|
          @stack_content.pop
        end
      end

      def set_code_space(cs)
        oldcs = @code_space
        @top_node.add_code_space(@code_space, cs)
        @code_space = cs
        asm = @top_node.asm_tab[cs]
        if asm == nil then
          @top_node.asm_tab[cs] = Assembler.new(cs)
        end

        oldcs
      end

      def assembler
        @top_node.asm_tab[@code_space]
      end

      def reset_using_reg
        @depth_reg = {}
      end

      def start_using_reg_aux(reg)
        if @depth_reg[reg] then
          assembler.with_retry do
            assembler.push(reg)
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
          assembler.with_retry do
            assembler.pop(reg)
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

      def to_key(offset = -1)
        @current_method_signature[offset]
      end
    end

    module Node
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
            cframe = frame_info
            asm.with_retry do
              asm.mov(TMPR2, BPR)
              depth.times do 
                asm.mov(TMPR2, cframe.offset_arg(0, TMPR2))
                cframe = cframe.previous_frame
              end
            end
            context.set_reg_content(TMPR2, cframe)
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

      def dump_context(context)
        print "---- Reg map ----\n"
        context.reg_content.each do |key, value|
          print "#{key}   #{value.class} \n"
        end

        print "---- Stack map ----\n"
        @frame_info.frame_layout.each_with_index do |vinf, i|
          ro = @frame_info.real_offset(i)
          if mlv = @modified_local_var[0][ro] then
            print "    #{mlv.class} \n"
          else
            print "    #{vinf.class} \n"
          end
        end
        context.stack_content.each do |value|
          print "    #{value.class} \n"
        end
      end
      
      def gen_make_argv(context)
        casm = context.assembler
        rarg = @arguments[3..-1]

        # make argv
        casm = context.assembler
        argbyte = rarg.size * AsmType::MACHINE_WORD.size
        casm.with_retry do
          casm.sub(SPR, argbyte)
        end
        context.cpustack_pushn(argbyte)

        rarg.each_with_index do |arg, i|
          context = arg.compile(context)
          context.ret_node.decide_type_once(context.to_key)
          rtype = context.ret_node.type
          context = rtype.gen_boxing(context)
          casm = context.assembler
          dst = OpIndirect.new(SPR, i * AsmType::MACHINE_WORD.size)
          if  context.ret_reg.is_a?(OpRegistor) or 
              context.ret_reg.is_a?(OpImmidiate32) or 
              context.ret_reg.is_a?(OpImmidiate8) then

            casm.with_retry do
              casm.mov(dst, context.ret_reg)
            end

          else
            casm.with_retry do
              casm.mov(TMPR, context.ret_reg)
              casm.mov(dst, TMPR)
            end
          end
          context.cpustack_setn(i * AsmType::MACHINE_WORD.size, context.ret_node)
        end

        # Copy Stack Pointer
        # TMPR2 doesnt need save. Because already saved in outside
        # of send node
        casm.with_retry do
          casm.mov(TMPR2, SPR)
        end
        context.set_reg_content(TMPR2, SPR)

        # stack, generate call ...
        context = yield(context, rarg)

        # adjust stack
        casm = context.assembler
        casm.with_retry do
          casm.add(SPR, argbyte)
        end
        context.cpustack_popn(argbyte)

        context
      end

      def gen_call(context, fnc, numarg)
        casm = context.assembler

        callpos = nil
        casm.with_retry do 
          dmy, callpos = casm.call_with_arg(fnc, numarg)
        end
        @var_return_address = casm.output_stream.var_base_address(callpos)
        dump_context(context)
        context
      end
    end
  end
end
