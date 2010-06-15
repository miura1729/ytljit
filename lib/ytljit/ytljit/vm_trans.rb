module YTLJit
  module VM
    class YARVContext
      include Node

      def initialize
        @the_top = TopTopNode.new(nil)
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
      end

      attr :the_top

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
            visit_symbol(code, ins, context)

          else
            opname = ins[0].to_s
            send(("visit_" + opname).to_sym, code, ins, context)
          end
        end
        visit_block_end(code, nil, context)
      end
    end

    module YARVTranslatorSimpleMixin
      include Node

      def visit_symbol(code, ins, context)
        context.current_local_label = ins
        curnode = context.current_node
        if (nllab = context.local_label_tab[ins]) == nil then
          nllab = LocalLabel.new(curnode, ins)
          context.local_label_tab[ins] = nllab
        end
        curnode.body = nllab
        context.current_node = nllab
      end

      def visit_block_start(code, ins, context)
        mtopnode = context.current_node

        locals = code.header['locals']
        args   = code.header['args']

        context.current_node = mtopnode.construct_frame_info(locals, args)
      end

      def visit_block_end(code, ins, context)
        curnode = context.current_node 
        case code.header['type']
        when :method
          nnode = MethodEndNode.new(curnode)
        when :block
          nnode = BlockEndNode.new(curnode)
        when :class
          nnode = ClassEndNode.new(curnode)
        when :top
          nnode = ClassEndNode.new(curnode)
        end
        curnode.body = nnode
        context.current_node = nnode
        curnode
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
        node = LocalVarRefNode.new(context.current_node, ins[1], ins[2])
        context.expstack.push node
      end

      def visit_setdynamic(code, ins, context)
        val = context.expstack.pop
        curnode = context.current_node
        node = LocalAssignNode.new(curnode, ins[1], ins[2], val)
        curnode.body = node
        context.current_node = node
      end

      # getinstancevariable
      # setinstancevariable
      # getclassvariable
      # setclassvariable
      
      def visit_getconstant(code, ins, context)
      end

      def visit_setconstant(code, ins, context)
      end

      # getglobal
      # setglobal
      
      def visit_putnil(code, ins, context)
        nnode = LiteralNode.new(nil, nil)
        context.expstack.push nnode
      end

      def visit_putself(code, ins, context)
        curnode = context.current_node
        nnode = LocalVarRefNode.new(curnode, 0, 0)
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
          mtopnode = MethodTopNode.new(curnode)
        when :class
          mtopnode = ClassTopNode.new(curnode)
        when :top
          raise "Maybe bug not appear top block."
        end
        ncontext.current_node = mtopnode

        ncontext.current_file_name = context.current_file_name
        ncontext.current_class_node = context.current_class_node
        mname = context.expstack.last
        ncontext.current_method_name = mname

        tr = VM::YARVTranslatorSimple.new([body])
        tr.translate(ncontext)
        context.expstack.push mtopnode
      end

      def visit_putstring(code, ins, context)
      end

      # concatstrings
      # tostring
      # toregexp
      # newarray
      # duparray
      # expandarray
      # concatarray
      # splatarray
      # checkincludearray
      # newhash
      # newrange

      def visit_pop(code, ins, context)
        node = context.expstack.pop
        curnode = context.current_node
        node.parent = curnode
        curnode.body = node
        context.current_node = node
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
        cnode = ClassTopNode.new(context.current_class_node, name)
        
        body = VMLib::InstSeqTree.new(code, ins[2])
        ncontext = YARVContext.new
        ncontext.current_file_name = context.current_file_name
        ncontext.current_node = cnode
        ncontext.current_class_node = cnode

        tr = VM::YARVTranslatorSimple.new([body])
        tr.translate(ncontext)

        context.current_class_node.nested_class_tab[name] = cnode
        context
      end

      def visit_send(code, ins, context)
        blk_iseq = ins[3]
        curnode = context.current_node
        numarg = ins[2]
        arg = []
        numarg.times do |i|
          argele = context.expstack.pop
          arg.push argele
        end
        
        if blk_iseq then
          body = VMLib::InstSeqTree.new(code, blk_iseq)
          ncontext = YARVContext.new
          ncontext.current_file_name = context.current_file_name
          ncontext.current_class_node = curnode
          btn = ncontext.current_node = BlockTopNode.new(curnode)

          tr = VM::YARVTranslatorSimple.new([body])
          tr.translate(ncontext)
          arg.push btn # block
        else
          arg.push LiteralNode.new(curnode, nil) # block(dymmy)
        end

        arg.push context.expstack.pop # self
 
        arg = arg.reverse

        func = MethodSelectNode.new(curnode, ins[1])
        cnode = context.current_node
        op_flag = ins[4]
        sn = SendNode.make_send_node(cnode, func, arg, op_flag)
        context.expstack.push sn
        context
      end

      def visit_invokesuper(code, ins, context)
      end

      def visit_invokeblock(code, ins, context)
      end

      def visit_leave(code, ins, context)
        visit_pop(code, ins, context)
      end
      
      def visit_throw(code, ins, context)
      end

      def visit_jump(code, ins, context)
      end

      def visit_branchif(code, ins, context)
      end

      def visit_branchunless(code, ins, context)
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

