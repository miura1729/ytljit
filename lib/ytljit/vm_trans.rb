module YTLJit
  module VM
    class YARVContext
      include Node

      def initialize
        @the_top = TopTopNode.new(nil, Object)
        @top_nodes = [@the_top]
        @current_file_name = nil
        @current_class_node = the_top
        @current_method_name = nil

        @enc_label = ""
        @enc_pos_in_source = ""
        @current_line_no = 0
        @current_local_label = nil

        @current_node = @the_top
        @vmtab = []

        @expstack = []
        @local_label_tab = {}

        @not_reached_pos = false
      end

      attr :the_top
      attr :top_nodes

      attr_accessor :current_file_name
      attr_accessor :current_class_node
      attr_accessor :current_method_name
      
      attr_accessor :enc_label
      attr_accessor :enc_pos_in_source
      attr_accessor :current_line_no
      attr_accessor :current_local_label

      attr_accessor :current_node
      attr          :vmtab

      attr          :expstack
      attr          :local_label_tab

      attr_accessor :not_reached_pos

      def import_object(klass, name, value)
        ctn = ClassTopNode.get_class_top_node(klass)
        if ctn == nil then
          ctn = ClassTopNode.new(@the_top, klass, klass.name)
        end
        valnode = LiteralNode.new(ctn, value)
        ctn.get_constant_tab[name] = valnode
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
                   context.current_method_name.to_s
            context.enc_label = lstr
          end
          translate_block(code, context)
        end
        
        context.the_top
      end

      def translate_block(code, context)
        visit_block_start(code, nil, context)
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
          context.local_label_tab[label] = nllab
        end
        
        nllab
      end

      def visit_symbol(code, ins, context)
        context.current_local_label = ins

        curnode = context.current_node
        nllab = get_vmnode_from_label(context, ins)
        
        unless curnode.is_a?(JumpNode)
          jmpnode = JumpNode.new(curnode, nllab)
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

        locals = code.header['locals']
        args   = code.header['misc'][:arg_size]

        context.current_node = mtopnode.construct_frame_info(locals, args)
      end

      def visit_block_end(code, ins, context)
      end

      def depth_of_block(code)
        dep = 0
        ccode = code
        while ccode.header['type'] == :block
          ccode = code.parent
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
        context.expstack.push node
      end

      def visit_setconstant(code, ins, context)
        klass = get_self_object(context)
        value = context.expstack.pop
        name = ins[1]
        curnode = context.current_node
        node = ConstantAssignNode.new(curnode, klass, name, value)
        curnode.body = node
        context.current_node = node
      end

      # getglobal
      # setglobal
      
      def visit_putnil(code, ins, context)
        nnode = LiteralNode.new(nil, nil)
        context.expstack.push nnode
      end

      def visit_putself(code, ins, context)
        curnode = context.current_node
        nnode = SelfRefNode.new(curnode)
        context.expstack.push nnode
      end
      
      def visit_putobject(code, ins, context)
        nnode = LiteralNode.new(nil, ins[1])
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
        ncontext.current_node = mtopnode
        ncontext.top_nodes.push mtopnode

        ncontext.current_file_name = context.current_file_name
        ncontext.current_class_node = context.current_class_node
        mname = context.expstack.last
        ncontext.current_method_name = mname

        tr = self.class.new([body])
        tr.translate(ncontext)
        context.expstack.push mtopnode
      end

      def visit_putstring(code, ins, context)
        nnode = LiteralNode.new(nil, ins[1])
        context.expstack.push nnode
      end

      # concatstrings
      # tostring
      # toregexp
      # newarray

      def visit_duparray(code, ins, context)
        nnode = LiteralNode.new(nil, ins[1])
        context.expstack.push nnode
      end

      # expandarray
      # concatarray
      # splatarray
      # checkincludearray
      # newhash
      # newrange

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
        context.expstack.push context.expstack.last
      end

      def visit_dupn(code, ins, context)
      end

      def visit_swap(code, ins, context)
      end

      # reput
      
      def visit_topn(code, ins, context)
      end

      def visit_setn(code, ins, context)
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
        context.expstack.push cvnode

        context
      end

      def visit_send(code, ins, context)
        blk_iseq = ins[3]
        curnode = context.current_node
        numarg = ins[2]
        seqno = ins[5]

        # regular arguments
        arg = []
        numarg.times do |i|
          argele = context.expstack.pop
          arg.push argele
        end
        
        # self
        arg.push context.expstack.pop

        # block
        if blk_iseq then
          body = VMLib::InstSeqTree.new(code, blk_iseq)
          ncontext = YARVContext.new
          ncontext.current_file_name = context.current_file_name
          ncontext.current_class_node = context.current_class_node
          btn = ncontext.current_node = BlockTopNode.new(curnode)
          ncontext.top_nodes.push btn

          tr = self.class.new([body])
          tr.translate(ncontext)
          arg.push btn # block
        else
          arg.push LiteralNode.new(curnode, nil) # block(dymmy)
        end

        # perv env
        arg.push LiteralNode.new(curnode, nil)

        arg = arg.reverse

        func = MethodSelectNode.new(curnode, ins[1])
        op_flag = ins[4]
        sn = SendNode.make_send_node(curnode, func, arg, op_flag, seqno)
        func.set_reciever(sn)
        context.expstack.push sn

        context
      end

      def visit_invokesuper(code, ins, context)
      end

      def visit_invokeblock(code, ins, context)
        curnode = context.current_node
        func = YieldNode.new(curnode)
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
        args.push LiteralNode.new(curnode, nil)

        # block
        args.push LiteralNode.new(curnode, nil)
        
        # perv env
        args.push LiteralNode.new(curnode, nil)

        args = args.reverse

        nnode = SendNode.new(curnode, func, args, op_flag, seqno)
        func.parent = nnode
        context.expstack.push nnode

        context
      end

      def visit_leave(code, ins, context)
        curnode = nil
        vnode = nil
        if context.top_nodes.last.name == :initialize then
          visit_pop(code, ins, context)
          curnode = context.current_node 
          vnode = SelfRefNode.new(curnode)
        else
          curnode = context.current_node 
          vnode = context.expstack.pop
        end

        srnode = SetResultNode.new(curnode, vnode)
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

        context.top_nodes.last.end_nodes.push nnode
        srnode.body = nnode
      end
      
      def visit_throw(code, ins, context)
      end

      def visit_jump(code, ins, context)
        curnode = context.current_node
        nllab = get_vmnode_from_label(context, ins[1])

        jpnode = JumpNode.new(curnode, nllab) 
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
        nllab.come_from[node] = nil

        curnode.body = node
        context.current_node = node
      end

      def visit_branchunless(code, ins, context)
        curnode = context.current_node
        nllab = get_vmnode_from_label(context, ins[1])

        cond = context.expstack.pop
        
        node = BranchUnlessNode.new(curnode, cond, nllab)
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

