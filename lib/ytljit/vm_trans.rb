module YTLJit
  module VM
    class YARVContext
      include Node

      def initialize
        @the_top = TopTopNode.new(nil, Object)
        @top_nodes = [@the_top]
        @current_file_name = nil
        @current_class_node = the_top
        @current_method_node = nil

        @enc_label = ""
        @enc_pos_in_source = ""
        @current_line_no = 0
        @current_local_label = nil

        @current_node = @the_top
        @vmtab = []

        @expstack = []
        @local_label_tab = {}

        @not_reached_pos = false

        @macro_method = nil
      end

      attr_accessor :the_top
      attr          :top_nodes

      attr_accessor :current_file_name
      attr_accessor :current_class_node
      attr_accessor :current_method_node
      
      attr_accessor :enc_label
      attr_accessor :enc_pos_in_source
      attr_accessor :current_line_no
      attr_accessor :current_local_label

      attr_accessor :current_node
      attr          :vmtab

      attr          :expstack
      attr          :local_label_tab

      attr_accessor :not_reached_pos

      attr_accessor :macro_method

      def import_object(klass, name, value)
        ctn = ClassTopNode.get_class_top_node(klass)
        if ctn == nil then
          ctn = ClassTopNode.new(@the_top, klass, klass.name)
        end
        valnode = LiteralNode.new(ctn, value)
        ctn.get_constant_tab[name] = valnode
      end

      def debug_info
        mname = nil
        if @current_method_node then
          mname = @current_method_node.get_constant_value
        end
        if mname then
          mname = mname[0]
        end

        [@current_file_name, 
         @current_class_node.name, 
         mname,
         @current_line_no]
      end
    end

    class YARVTranslatorBase
      def initialize(iseqs)
        @iseqs = iseqs
      end

      def translate(context = nil)
        if context == nil then
          context = YARVContext.new
        end
        @iseqs.each do |code|
          pos = "#{code.header['filename']}:#{context.current_line_no}"
          context.enc_pos_in_source = pos
          if code.header['type'] == :block then
            lstr = context.enc_label + "+blk+" + 
                   context.current_method_node.to_s
            context.enc_label = lstr
          end
          translate_block(code, context)
        end
        
        context.the_top
      end

      def translate_main(code, context)
        code.body.each do |ins|
          pos = "#{code.header['filename']}:#{context.current_line_no}"
          context.enc_pos_in_source = pos
          if ins == nil then
            # do nothing
          elsif ins.is_a?(Fixnum) then
            # line no
            context.current_line_no = ins
          elsif ins.is_a?(Symbol) then
            context.not_reached_pos = false
            visit_symbol(code, ins, context)

          elsif !context.not_reached_pos then
            opname = ins[0].to_s
            send(("visit_" + opname).to_sym, code, ins, context)
          end
        end
      end

      def translate_block(code, context)
        visit_block_start(code, nil, context)
        translate_main(code, context)
        visit_block_end(code, nil, context)
      end
    end

    module YARVTranslatorSimpleMixin
      include Node

      def get_vmnode_from_label(context, label)
        curnode = context.current_node
        nllab = context.local_label_tab[label]
        if nllab == nil then
          nllab = LocalLabel.new(curnode, label)
          nllab.debug_info = context.debug_info
          context.local_label_tab[label] = nllab
        end
        
        nllab
      end

      def gen_arg_node(context, sendnode, func, args)
        curnode = context.current_node
        nnode = sendnode.new(curnode, func, args, 0, 0)
        nnode.debug_info = context.debug_info
        func.parent = nnode
        nnode
      end

      def visit_symbol(code, ins, context)
        context.current_local_label = ins

        curnode = context.current_node
        nllab = get_vmnode_from_label(context, ins)
        
        unless curnode.is_a?(JumpNode)
          jmpnode = JumpNode.new(curnode, nllab)
          jmpnode.debug_info = context.debug_info
          nllab.parent = jmpnode

          val = context.expstack.pop
          nllab.come_from[jmpnode] = val
        
          curnode.body = jmpnode
          jmpnode.body = nllab
          context.expstack.push nllab.value_node
        end
        
        context.current_node = nllab
      end

      def visit_block_start(code, ins, context)
        mtopnode = context.current_node
        if !mtopnode.is_a?(TopNode) then
          oldtop = context.the_top
          mtopnode = TopTopNode.new(nil, Object)
          mtopnode.debug_info = context.debug_info
          context.the_top = mtopnode
          oldtop.parent = mtopnode
          mtopnode.init_node = oldtop
        end

        context.macro_method = nil

        locals = code.header['locals']
        arg_size   = code.header['misc'][:arg_size]
        args   = code.header['args']
        (arg_size - locals.size).times do 
          locals.push nil
        end
        
        cnode = mtopnode.construct_frame_info(locals, arg_size, args)
        context.current_node = cnode
      end

      def visit_block_end(code, ins, context)
        curnode = context.current_node
        top = context.top_nodes.last
        if top.class == MethodTopNode then
          if context.macro_method then
            code = top.to_ruby(ToRubyContext.new).ret_code.last
#            print code
            proc = eval("lambda" + code)
            SendNode.get_macro_tab[top.name] = proc
          end
        end
      end

      def depth_of_block(code)
        dep = 0
        ccode = code
        while ccode.header['type'] == :block
          ccode = ccode.parent
          dep += 1
        end
        
        dep
      end

      def visit_getlocal(code, ins, context)
        dep = depth_of_block(code)
        visit_getdynamic(code, [:getlocal, ins[1], dep], context)
      end

      def visit_setlocal(code, ins, context)
        dep = depth_of_block(code)
        visit_setdynamic(code, [:setlocal, ins[1], dep], context)
      end

      # getspecial
      # setspecial

      def visit_getdynamic(code, ins, context)
        # + 3 mean prtv_env/pointer to block function/self
        dep = ins[2]
        curcode = code
        dep.times do
          curcode = curcode.parent
        end
        offset = curcode.header['misc'][:local_size] + 3 - ins[1]
        node = LocalVarRefNode.new(context.current_node, offset, dep)
        node.debug_info = context.debug_info
        context.expstack.push node
      end

      def visit_setdynamic(code, ins, context)
        dep = ins[2]
        curcode = code
        dep.times do
          curcode = curcode.parent
        end
        val = context.expstack.pop
        curnode = context.current_node
        offset = curcode.header['misc'][:local_size] + 3 - ins[1]
        node = LocalAssignNode.new(curnode, offset, dep, val)
        node.debug_info = context.debug_info
        if context.expstack[-1] == val then
          varref = LocalVarRefNode.new(context.current_node, offset, dep)
          varref.debug_info = context.debug_info
          context.expstack[-1] = varref
        end
        curnode.body = node
        context.current_node = node
      end

=begin
      def visit_getinstancevariable(code, ins, context)
      end

      def visit_setinstancevariable(code, ins, context)
      end
=end

      # getclassvariable
      # setclassvariable

      def get_self_object(context)
        klass = context.expstack.pop
        case klass
        when ConstantRefNode
          klass = klass.value_node

        when LiteralNode
          klass = klass.value
          if klass == nil then
            klass = context.current_class_node
          end

        when SpecialObjectNode
          if klass.kind == 3 then
            klass = context.current_class_node
          else
            raise "Unkown special object kind = #{klass.kind}"
          end

        else
          raise "Umkonwn node #{klass.class}"
        end

        klass
      end
      
      def visit_getconstant(code, ins, context)
        klass = get_self_object(context)
        name = ins[1]
        curnode = context.current_node
        node = ConstantRefNode.new(curnode, klass, name)
        node.debug_info = context.debug_info
        context.expstack.push node
      end

      def visit_setconstant(code, ins, context)
        klass = get_self_object(context)
        value = context.expstack.pop
        name = ins[1]
        curnode = context.current_node
        node = ConstantAssignNode.new(curnode, klass, name, value)
        node.debug_info = context.debug_info
        curnode.body = node
        context.current_node = node
      end

      # getglobal
      # setglobal
      
      def visit_putnil(code, ins, context)
        nnode = LiteralNode.new(nil, nil)
        nnode.debug_info = context.debug_info
        context.expstack.push nnode
      end

      def visit_putself(code, ins, context)
        curnode = context.current_node
        nnode = SelfRefNode.new(curnode)
        nnode.debug_info = context.debug_info
        context.expstack.push nnode
      end
      
      def visit_putobject(code, ins, context)
        nnode = LiteralNode.new(nil, ins[1])
        nnode.debug_info = context.debug_info
        context.expstack.push nnode
      end

      def visit_putspecialobject(code, ins, context)
        context.expstack.push SpecialObjectNode.new(nil, ins[1])
      end

      def visit_putiseq(code, ins, context)
        body = VMLib::InstSeqTree.new(code, ins[1])
        curnode = context.current_node
        ncontext = YARVContext.new

        case body.header['type']
        when :block
          mtopnode = BlockTopNode.new(curnode)
        when :method
          mtopnode = MethodTopNode.new(curnode, body.header['name'].to_sym)
        when :class
          mtopnode = ClassTopNode.new(curnode, body.header['name'].to_sym)
        when :top
          raise "Maybe bug not appear top block."
        end
        mtopnode.debug_info = context.debug_info
        ncontext.current_node = mtopnode
        ncontext.top_nodes.push mtopnode

        ncontext.current_file_name = context.current_file_name
        ncontext.current_class_node = context.current_class_node
        mname = context.expstack.last
        ncontext.current_method_node = mname

        tr = self.class.new([body])
        tr.translate(ncontext)
        context.macro_method = ncontext.macro_method
        context.expstack.push mtopnode
      end

      def visit_putstring(code, ins, context)
        nnode = LiteralNode.new(nil, ins[1])
        nnode.debug_info = context.debug_info
        context.expstack.push nnode
      end

      def visit_concatstrings(code, ins, context)
        curnode = context.current_node
        numarg = ins[1]
        nnode = context.expstack[-numarg]
        (numarg - 1).times do |i|
          func = FixArgCApiNode.new(curnode, "rb_str_append")
          args = [nnode, context.expstack[i - numarg + 1]]
          nnode = gen_arg_node(context, RetStringSendNode, func, args)
        end

        numarg.times do
          context.expstack.pop
        end
        context.expstack.push nnode
      end

      def visit_tostring(code, ins, context)
        curnode = context.current_node
        func = FixArgCApiNode.new(curnode, "rb_obj_as_string")
        args = []
        argele = context.expstack.pop
        args.push argele
        nnode = gen_arg_node(context, RetStringSendNode, func, args)
        context.expstack.push nnode
      end

      # toregexp

      def newinst_to_sendnode(argnum, klass, code, ins, context)
        arg = []
        argnum.times {
          arg.push context.expstack.pop
        }
        curnode = context.current_node
        arg.push ConstantRefNode.new(curnode, nil, klass.name.to_sym)

        arg.reverse.each do |c|
          context.expstack.push c
        end

        visit_send(code, [:send, :new, argnum, nil, 0, nil], context)
      end

      def visit_newarray(code, ins, context)
        curnode = context.current_node
        func = FixArgCApiNode.new(curnode, "rb_ary_new3")
        argnum = ins[1]
        argnumnode = LiteralNode.new(nil, argnum)
        args = []
        argnum.times do
          argele = context.expstack.pop
          args.push argele
        end
        args.push argnumnode
        args = args.reverse
        nnode = gen_arg_node(context, RetArraySendNode, func, args)
        context.expstack.push nnode
      end

      def visit_duparray(code, ins, context)
        nnode = LiteralNode.new(nil, ins[1])
        nnode.debug_info = context.debug_info
        context.expstack.push nnode
      end

      # expandarray
      # concatarray
      # splatarray
      # checkincludearray
      # newhash

      def visit_newrange(code, ins, context)
        exclflag = LiteralNode.new(nil, ins[1] == 1)
        context.expstack.push exclflag
        newinst_to_sendnode(3, Range, code, ins, context)
      end
        
      def visit_pop(code, ins, context)
        node = context.expstack.pop
        if node == nil then
          # Maybe push instruction deleted by optimize
          node = LiteralNode.new(nil, nil)
        end

        curnode = context.current_node
        node.parent = curnode
        curnode.body = node
        if node.is_a?(HaveChildlenMixin) then
          context.current_node = node
        end

        context
      end

      def visit_dup(code, ins, context)
        orgnode = context.expstack.pop
        nnode = MultiplexNode.new(orgnode)
        context.expstack.push nnode
        context.expstack.push nnode
      end

      def visit_dupn(code, ins, context)
        raise "foo"
      end

      def visit_swap(code, ins, context)
        val0 = context.expstack.pop
        val1 = context.expstack.pop
        context.expstack.push val0
        context.expstack.push val1
      end

      # reput
      
      def visit_topn(code, ins, context)
        raise
        n = ins[1] + 1
        context.expstack.push context.expstack[-n]
      end

      def visit_setn(code, ins, context)
        n = ins[1] + 1
        orgnode = context.expstack.last
        nnode = MultiplexNode.new(orgnode)
        context.expstack[-n] = nnode
        context.expstack[-1] = nnode
      end

      # adjuststack
      # defined

      def visit_trace(code, ins, context)
      end

      def visit_defineclass(code, ins, context)
        name = ins[1]
        supklsnode = context.expstack.pop
        defat = context.expstack.pop
        clsobj = context.current_class_node.klass_object
        klassobj = nil
        begin
          klassobj = clsobj.const_get(name, true)
        rescue NameError
        end

        if klassobj == nil then
          klassnode = context.current_class_node.constant_tab[name]
          if klassnode then
            klassobj = klassnodne.klass_object
            
          else
            supklass = nil
            case supklsnode
            when LiteralNode
              supklass = supklsnode.value
              if supklass == nil then
                supklass = Object
              end

            when ConstantRefNode
              supnode = supklsnode.value_node
              if supnode.is_a?(ClassTopNode) then
                supklass = supnode.klass_object
              else
                raise "Not class #{supnode.class}"
              end

            else
              raise "Not support #{supklsnode.class}"
            end

            case ins[3]
            when 0
              klassobj = Class.new(supklass)
              
            when 2
              klassobj = Module.new
            end
          end
          clsobj.const_set(name, klassobj)
        end
        RubyType::define_wraped_class(klassobj, RubyType::RubyTypeBoxed)
        cnode = ClassTopNode.new(context.current_class_node, klassobj, name)
        cnode.debug_info = context.debug_info
        context.current_class_node.constant_tab[name] = cnode
        
        body = VMLib::InstSeqTree.new(code, ins[2])
        ncontext = YARVContext.new
        ncontext.current_file_name = context.current_file_name
        ncontext.current_node = cnode
        ncontext.current_class_node = cnode
        ncontext.top_nodes.push cnode

        tr = self.class.new([body])
        tr.translate(ncontext)

        curnode = context.current_node
        cvnode = ClassValueNode.new(curnode, cnode)
        cvnode.debug_info = context.debug_info
        context.expstack.push cvnode

        context
      end

      def visit_send(code, ins, context)
        curnode = context.current_node
        numarg = ins[2]
        blk_iseq = ins[3]
        op_flag = ins[4]
        seqno = ins[5]

        # regular arguments
        arg = []
        numarg.times do |i|
          argele = context.expstack.pop
          arg.push argele
        end
        
        # self
        slf = context.expstack.pop
        if (op_flag & (0b11 << 3)) != 0 and # fcall, vcall
            slf.is_a?(LiteralNode) and 
            slf.value == nil and 
            context.current_class_node.name != :top then
          slf = SelfRefNode.new(curnode)
        end
        arg.push slf

        # block
        if blk_iseq then
          body = VMLib::InstSeqTree.new(code, blk_iseq)
          ncontext = YARVContext.new
          ncontext.current_file_name = context.current_file_name
          ncontext.current_class_node = context.current_class_node
          ncontext.current_method_node = context.current_method_node
          btn = ncontext.current_node = BlockTopNode.new(curnode)
          ncontext.top_nodes.push btn

          tr = self.class.new([body])
          tr.translate(ncontext)
          btn.debug_info = context.debug_info
          context.macro_method = ncontext.macro_method

          arg.push btn # block
        else
          argnode = LiteralNode.new(curnode, nil)
          argnode.debug_info = context.debug_info
          arg.push argnode      # block(dymmy)
        end

        # perv env
        argnode = LiteralNode.new(curnode, nil)
        argnode.debug_info = context.debug_info
        arg.push argnode

        arg = arg.reverse

        func = MethodSelectNode.new(curnode, ins[1])
        sn = SendNode.make_send_node(curnode, func, arg, op_flag, seqno)
        if sn.is_a?(SendEvalNode) then
          if context.macro_method == nil then
            context.macro_method = true
          end
        end

        if sn.is_a?(SendNode) then
          sn.debug_info = context.debug_info
          func.set_reciever(sn)
          context.expstack.push sn

        elsif sn.is_a?(Array)
          # macro(including eval method). execute in compile time and
          # compile eval strings.
          val, evalstr = sn
          evalstr = evalstr.join("\n")
          is = RubyVM::InstructionSequence.compile(
                   evalstr, "macro #{ins[1]}", "", 0, YTL::ISEQ_OPTS
               ).to_a
          ncode = VMLib::InstSeqTree.new(code, is)
          ncode.body.pop        # Chop leave instruction
          translate_main(ncode, context)
#          context.expstack.push val
        else
          raise "Unexcepted data type #{sn.class}"
        end

        context
      end

      def visit_invokesuper(code, ins, context)
      end

      def visit_invokeblock(code, ins, context)
        curnode = context.current_node
        func = YieldNode.new(curnode)
        func.debug_info = context.debug_info
        numarg = ins[1]
        op_flag = ins[2]
        seqno = ins[3]

        # regular arguments
        args = []
        numarg.times do |i|
          argele = context.expstack.pop
          args.push argele
        end

        frameinfo = func.frame_info
        roff = frameinfo.real_offset(0)  # offset of prevenv
        framelayout = frameinfo.frame_layout

        # self
        argnode = LiteralNode.new(curnode, nil)
        argnode.debug_info = context.debug_info
        args.push argnode

        # block
        argnode = LiteralNode.new(curnode, nil)
        argnode.debug_info = context.debug_info
        args.push argnode
        
        # perv env
        argnode = LiteralNode.new(curnode, nil)
        argnode.debug_info = context.debug_info
        args.push argnode

        args = args.reverse

        nnode = SendNode.new(curnode, func, args, op_flag, seqno)
        nnode.debug_info = context.debug_info
        func.parent = nnode
        context.expstack.push nnode

        context
      end

      def visit_leave(code, ins, context)
        curnode = nil
        vnode = nil

        if context.top_nodes.last.name == :initialize then
          # This is necessary. So it decides type of new method
          visit_pop(code, ins, context)
          curnode = context.current_node 
          vnode = SelfRefNode.new(curnode)
          vnode.debug_info = context.debug_info
        else
          curnode = context.current_node 
          vnode = context.expstack.pop
          vnode.debug_info = context.debug_info
        end

        srnode = SetResultNode.new(curnode, vnode)
        srnode.debug_info = context.debug_info
        curnode.body = srnode

        context.current_node = srnode

        case code.header['type']
        when :method
          nnode = MethodEndNode.new(srnode)
        when :block
          nnode = BlockEndNode.new(srnode)
        when :class
          nnode = ClassEndNode.new(srnode)
        when :top
          nnode = ClassEndNode.new(srnode)
        end
        nnode.debug_info = context.debug_info

        context.top_nodes.last.end_nodes.push nnode
        srnode.body = nnode
      end
      
      def visit_throw(code, ins, context)
      end

      def visit_jump(code, ins, context)
        curnode = context.current_node
        nllab = get_vmnode_from_label(context, ins[1])

        jpnode = JumpNode.new(curnode, nllab) 
        jpnode.debug_info = context.debug_info
        jpnode.body = nllab

        val = context.expstack.pop
        nllab.come_from[jpnode] = val

        curnode.body = jpnode
        context.current_node = jpnode
        context.not_reached_pos = true
      end

      def visit_branchif(code, ins, context)
        curnode = context.current_node
        nllab = get_vmnode_from_label(context, ins[1])
 
        cond = context.expstack.pop
       
        node = BranchIfNode.new(curnode, cond, nllab)
        node.debug_info = context.debug_info
        nllab.come_from[node] = nil

        curnode.body = node
        context.current_node = node
      end

      def visit_branchunless(code, ins, context)
        curnode = context.current_node
        nllab = get_vmnode_from_label(context, ins[1])

        cond = context.expstack.pop
        
        node = BranchUnlessNode.new(curnode, cond, nllab)
        node.debug_info = context.debug_info
        nllab.come_from[node] = nil

        curnode.body = node
        context.current_node = node
      end

      # getinlinecache
      # onceinlinecache
      # setinlinecache

      # Optimized instructions is not support. You must compile option for
      # avoid optimized instructions.
    end

    class YARVTranslatorSimple<YARVTranslatorBase
      include YARVTranslatorSimpleMixin
    end
  end
end

