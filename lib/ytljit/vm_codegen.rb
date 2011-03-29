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
        @modified_instance_var = Hash.new
        @yield_node = []

        # Options from user
        @options = {}
      end

      attr          :top_node
      attr_accessor :modified_local_var
      attr_accessor :modified_instance_var
      attr_accessor :yield_node
      attr_accessor :options

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

        @modified_local_var[-1] = res
      end
    end
    
    class TypeInferenceContext
      def initialize(tnode)
        @top_node = tnode
        @current_method_signature_node = [[]]
        @current_method = [tnode]
        @convergent = false
        @visited_top_node = {}
        # Options from user
        @options = {}
      end

      def to_signature(offset = -1, cache = {})
        if offset.is_a?(Node::TopNode) then
          i = -1
          while @current_method[i] and @current_method[i] != offset
            i = i - 1
          end
          if @current_method[i] == offset then
            offset = i
          else
            # This is legal this TopNode has only one signature 
            sigc = offset.signature_cache
            if sigc.size == 1 then
              return sigc[0]
            else
              raise "I can't type inference..."
            end
          end
        end

        cursignode = @current_method_signature_node[offset]
        curmethod = @current_method[offset]

        sigc = curmethod.signature_cache
        if sigc.size == 1 then
          return sigc[0]
        end
        
        if rsig = cache[cursignode] then
          return rsig
        end

        if curmethod.is_a?(Node::ClassTopNode) then
          rsig = to_signature_aux(cursignode, offset, cache)
          cache[cursignode] = rsig
          rsig

        elsif curmethod.is_a?(Node::TopNode) then
          prevsig = to_signature(offset - 1, cache)
          rsig = to_signature_aux2(curmethod, cursignode, 
                                   prevsig, offset, cache)
          cache[cursignode] = rsig
          rsig
          
        else
          raise "Maybe bug"
=begin
          prevsig = to_signature(offset - 1, cache)
          mt, slf = curmethod.get_send_method_node(prevsig)

          rsig = to_signature_aux2(mt, cursignode, prevsig, offset, cache)
          cache[cursignode] = rsig
          return rsig
=end
        end
      end

      def to_signature_aux(cursignode, offset, cache)
        res = cursignode.map { |enode|
          enode.decide_type_once(to_signature(offset - 1, cache))
        }
        
        res
      end

      def to_signature_aux2(mt, args, cursig, offset, cache)
        res = []
        args.each do |ele|
          ele.decide_type_once(cursig)
          res.push ele.type
        end

        if mt and (ynode = mt.yield_node[0]) then
          yargs = ynode.arguments
          push_signature(args, mt)
          ysig = to_signature_aux3(yargs, -1, cache)
          args[1].type = nil
          args[1].decide_type_once(ysig)
          res[1] = args[1].type
          pop_signature
        end
        
        res
      end

      def to_signature_aux3(cursignode, offset, cache)
        if res = cache[cursignode] then
          return res
        end

        res = cursignode.map { |enode|
          cursignode2 = @current_method_signature_node[offset]
          sig = to_signature_aux3(cursignode2, offset - 1, cache)
          enode.decide_type_once(sig)
        }
        cache[cursignode] = res
        
        res
      end

      def push_signature(signode, method)
        @current_method_signature_node.push signode
        @current_method.push method
      end

      def pop_signature
        @current_method.pop
        @current_method_signature_node.pop
      end

      attr          :top_node
      attr          :current_method_signature_node
      attr_accessor :convergent
      attr_accessor :visited_top_node
      attr_accessor :options
    end

    class CompileContext
      include AbsArch
      def initialize(tnode)
        @top_node = tnode
        @prev_context = nil
        @code_space = nil

        # Signature of current compiling method
        # It is array, because method may be nest.
        @current_method_signature = []
        
        # RETR(EAX, RAX) or RETFR(STO, XM0) or Immdiage object
        @ret_reg = RETR
        @ret_reg2 = RETR
        @ret_node = nil
#        @depth_reg = {}
        @depth_reg = Hash.new(0)
        @stack_content = []
        @reg_content = {}

        # Use only type inference compile mode
        @slf = nil

        # Options from user
        @options = {}
      end

      attr          :top_node
      attr_accessor :prev_context
      attr          :code_space

      attr          :current_method_signature

      attr          :depth_reg
      attr_accessor :ret_reg
      attr_accessor :ret_reg2
      attr_accessor :ret_node

      attr          :reg_content
      attr_accessor :stack_content

      attr_accessor :slf

      attr_accessor :options

      def set_reg_content(dst, val)
        if dst.is_a?(FunctionArgument) then
          dst = dst.dst_opecode
        end
        if dst.is_a?(OpRegistor) then
          if val.is_a?(OpRegistor) and @reg_content[val] then
            @reg_content[dst] = @reg_content[val]
          else
            @reg_content[dst] = val
          end
        elsif dst.is_a?(OpIndirect) then
          wsiz = AsmType::MACHINE_WORD.size
          if dst.reg == SPR then
            if val.is_a?(OpRegistor) and @reg_content[val] then
              cpustack_setn(dst.disp.value / wsiz, @reg_content[val])
            else
              cpustack_setn(dst.disp.value / wsiz, val)
            end
          end
          if dst.reg == BPR then
            if val.is_a?(OpRegistor) and @reg_content[val] then
              cpustack_setn(-dst.disp.value / wsiz + 3, @reg_content[val])
            else
              cpustack_setn(-dst.disp.value / wsiz + 3, val)
            end
          end
        elsif dst.is_a?(OpImmidiate) then
          # do nothing and legal

        else
#          pp "foo"
#          pp dst
        end
      end

      def cpustack_push(reg)
        if @reg_content[reg] then
          @stack_content.push @reg_content[reg]
        else
          @stack_content.push reg
        end
      end

      def cpustack_pop(reg)
        cont = @stack_content.pop
        if !cont.is_a?(OpRegistor) then
          @reg_content[reg] = cont
        end
      end

      def cpustack_setn(offset, val)
        if offset >= -@stack_content.size then
          @stack_content[offset] = val
        else
          # Modify previous stack (maybe as arguments)
        end
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
        @depth_reg = Hash.new(0)
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
          if reg != TMPR and reg != XMM0 then
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
        if @depth_reg[reg] != -1 then
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
          if reg != TMPR and reg != XMM0 then
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

      def start_arg_reg(kind = FUNC_ARG)
        asm = assembler
        gen = asm.generator
        used_arg_tab = gen.funcarg_info.used_arg_tab
        if used_arg_tab.last then
#          p "#{used_arg_tab.last.keys} #{caller[0]} #{@name}"
          used_arg_tab.last.keys.each do |rno|
            start_using_reg(kind[rno])
          end
        end
      end

      def end_arg_reg(kind = FUNC_ARG)
        asm = assembler
        gen = asm.generator
        used_arg_tab = gen.funcarg_info.used_arg_tab
        if used_arg_tab.last then
          used_arg_tab.last.keys.reverse.each do |rno|
            end_using_reg(kind[rno])
          end
        end
      end

      def to_signature(offset = -1)
        @current_method_signature[offset]
      end

      def push_signature(signode, method)
        sig = signode.map { |enode|
          enode.decide_type_once(to_signature)
        }
        @current_method_signature.push sig
      end

      def pop_signature
        @current_method_signature.pop
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
            asm.push(TMPR)
            asm.push(THEPR)
            asm.push(BPR)
            asm.mov(BPR, SPR)
          end
          context.cpustack_push(BPR)
          context.cpustack_push(TMPR)
          context.cpustack_push(THEPR)
          context.cpustack_push(SPR)
            
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
            asm.pop(THEPR) if @is_escape != :export_object
            asm.mov(SPR, BPR)
            asm.pop(BPR)
          end
          context.stack_content = []

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

    module CommonCodeGen
      include AbsArch

      def gen_alloca(context, siz)
        asm = context.assembler
        case siz
        when Integer
          add = lambda { 
            address_of("ytl_arena_alloca")
          }
          alloca = OpVarMemAddress.new(add)
          asm.with_retry do
            asm.mov(TMPR, siz)
            asm.mov(FUNC_ARG[0], TMPR)
          end
          context = gen_call(context, alloca, 1)
          asm.with_retry do
            asm.mov(THEPR, RETR)
          end
        else
          raise "Not implemented yet variable alloca"
        end
        context.ret_reg = THEPR
        context
      end

      def gen_save_thepr(context)
        casm = context.assembler
        arenaaddr = context.top_node.get_arena_address
        casm.with_retry do
          casm.mov(TMPR, arenaaddr)
          casm.mov(INDIRECT_TMPR, THEPR)
        end
        context
      end

      def gen_call(context, fnc, numarg, slf = nil)
        casm = context.assembler

        callpos = nil
        casm.with_retry do 
          dmy, callpos = casm.call_with_arg(fnc, numarg)
        end
        context.end_using_reg(fnc)
        vretadd = casm.output_stream.var_base_address(callpos)
        cpuinfo = []
        if slf then
          cpuinfo.push slf
        else
          cpuinfo.push self
        end
        cpuinfo.push context.reg_content.dup
        cpuinfo.push context.stack_content.dup
        context.top_node.frame_struct_array.push [vretadd, cpuinfo]
        
        if context.options[:dump_context] then
          dump_context(context)
        end
        context
      end

      def dump_context(context)
        print "---- Reg map ----\n"
        context.reg_content.each do |key, value|
          print "#{key}   #{value.class} \n"
        end

        print "---- Stack map ----\n"
=begin
        @frame_info.frame_layout.each_with_index do |vinf, i|
          ro = @frame_info.real_offset(i)
          if mlv = @modified_local_var.last[0][ro] then
            print "    #{mlv.class} \n"
          else
            print "    #{vinf.class} \n"
          end
        end
=end
        context.stack_content.each do |value|
          print "    #{value.class} \n"
        end
      end
    end

    module SendNodeCodeGen
      include AbsArch
      include CommonCodeGen

      def gen_make_argv(context, rarg = nil, argcomphook = nil)
        casm = context.assembler
        if rarg == nil then
          rarg = @arguments[3..-1]
        end
        cursig = context.to_signature

        # make argv
        argbyte = rarg.size * AsmType::MACHINE_WORD.size
        casm.with_retry do
          casm.sub(SPR, argbyte)
        end
        context.cpustack_pushn(argbyte)

        rarg.each_with_index do |arg, i|
          rtype = nil
          if argcomphook then
            rtype = argcomphook.call(context, arg, i)
          else
            context = arg.compile(context)
            context.ret_node.decide_type_once(cursig)
            rtype = context.ret_node.type
          end
          context = rtype.gen_boxing(context)
          dst = OpIndirect.new(SPR, i * AsmType::MACHINE_WORD.size)
          if context.ret_reg.is_a?(OpRegistor) or 
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
          context.cpustack_setn(i, context.ret_node)
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
        casm.with_retry do
          casm.add(SPR, argbyte)
        end
        context.cpustack_popn(argbyte)

        context
      end
    end
  end
end
