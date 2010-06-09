module YTLJit
  module VM
    class YARVContext
      def initialize
        @current_file_name = nil
        @current_class_name = nil
        @current_method_name = nil

        @enc_label = ""
        @enc_pos_in_source = ""
        @current_line_no = 0
        @current_local_label = nil

        @current_vm = nil
        @vmtab = []

        @expstack = []
        @local_label_tab = {}
      end

      attr_accessor :current_file_name
      attr_accessor :current_class_name
      attr_accessor :current_method_name
      
      attr_accessor :enc_label
      attr_accessor :enc_pos_in_source
      attr_accessor :current_line_no
      attr_accessor :current_local_label

      attr_accessor :current_vm
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
            lstr = context.enc_label + "+blk+" + code.info[2].to_s
            context.enc_label = lstr
          end
          translate_block(code, context)
        end
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
            visit_symbol(code, nil, context)

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
        cvm = context.current_vm
        cvm = LocalLabel.new(cvm, ins)
        context.local_label_tab[ins] = cvm
        context.current_vm = cvm
      end

      def visit_block_start(code, ins, context)
        mtopnode = nil
        case code.header['type']
        when :block
          mtopnode = BlockTopNode.new(context.current_vm)
        when :method
          mtopnode = MethodTopNode.new(context.current_vm)
        when :class
          mtopnode = ClassTopNode.new(context.current_vm)
        when :top
          mtopnode = TopNode.new(context.current_vm)
        end

        locals = code.header['locals']
        args   = code.header['args']

        context.current_vm = mtopnode.construct_frame_info(locals, args)
        context.current_vm.inspect_by_graph
      end

      def visit_block_end(code, ins, context)
      end

      def visit_local_block_start(code, ins, context)
      end

      def visit_local_block_end(code, ins, context)
      end

      def visit_getlocal(code, ins, context)
      end

      def visit_setlocal(code, ins, context)
      end

      # getspecial
      # setspecial

      def visit_getdynamic(code, ins, context)
      end

      def visit_setdynamic(code, ins, context)
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
      end

      def visit_putself(code, ins, context)
      end
      
      def visit_putobject(code, ins, context)
        nnode = LiteralNode.new(context.current_vm, ins[1])
        context.expstack.push nnode
      end

      def visit_putspecialobject(code, ins, context)
      end

      def visit_putiseq(code, ins, context)
        body = VMLib::InstSeqTree.new(code, ins[1])
        ncontext = YARVContext.new
        ncontext.current_file_name = context.current_file_name
        ncontext.current_vm = context.current_vm
        ncontext.current_class_name = context.current_class_name
        mname = context.expstack.pop
        ncontext.current_method_name = mname.value

        tr = VM::YARVTranslatorSimple.new([body])
        tr.translate(ncontext)
        context.expstack.push ncontext.current_vm
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
      end

      def visit_dup(code, ins, context)
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
        
        body = VMLib::InstSeqTree.new(code, ins[2])
        ncontext = YARVContext.new
        ncontext.current_file_name = context.current_file_name
        ncontext.current_vm = context.current_vm
        ncontext.current_class_name = name

        tr = VM::YARVTranslatorSimple.new([body])
        tr.translate(ncontext)
      end

      def visit_send(code, ins, context)
      end

      def visit_invokesuper(code, ins, context)
      end

      def visit_invokeblock(code, ins, context)
      end

      def visit_leave(code, ins, context)
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

