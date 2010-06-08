module YTLJit
  module VM
    class YARVContext
      def initialize
        @enc_label = ""
        @enc_pos_in_source = ""
        @current_line_no = 0
        @current_local_label = nil

        @current_vm = nil
        @vmtab = []
      end
      
      attr_accessor :enc_label
      attr_accessor :enc_pos_in_source
      attr_accessor :current_line_no
      attr_accessor :current_local_label

      attr_accessor :current_vm
      attr          :vmtab
    end

    class YARVTranslatorBase
      def initialize(iseqs)
        @iseqs = iseqs
      end

      def translate
        context = YARVContext.new
        @iseqs.each do |iseq|
          action = lambda do |code, info|
            pos = "#{code.header['filename']}:#{context.current_line_no}"
            context.enc_pos_in_source = pos
            if code.header['type'] == :block then
              lstr = context.enc_label + "+blk+" + code.info[2].to_s
              context.enc_label = lstr
            end
            translate_block(code, info, context)
          end
          iseq.traverse_code([nil, nil, nil, nil], action)
        end
      end

      def translate_block(code, info, context)
        isblkfst = true
        code.lblock_list.each do |ln|
          islocfst = true
          context.current_local_label = ln
          code.lblock[ln].each do |ins|
            if ins == nil then
              # do nothing
            elsif ins.is_a?(Fixnum) then
              # label
              context.current_line_no = ins
            else
              pos = "#{code.header['filename']}:#{context.current_line_no}"
              context.enc_pos_in_source = pos

              if isblkfst then
                isblkfst = false
                visit_block_start(code, nil, info, context)
              end

              if islocfst then
                islocfst = false
                visit_local_block_start(code, ln, info, context)
              end

              opname = ins[0].to_s
              send(("visit_" + opname).to_sym, code, ins, info, context)
            end
          end
          visit_local_block_end(code, nil, info, context)
        end
        visit_block_end(code, nil, info, context)
      end
    end

    module YARVTranslatorSimpleMixin
      include Node

      def visit_block_start(code, ins, info, context)
        mtopnode = MethodTopNode.new(context.current_vm)

        locals = code.header['locals']
        args   = code.header['args']

        p context.current_vm = mtopnode.construct_frame_info(locals, args)
      end

      def visit_block_end(code, ins, info, context)
      end

      def visit_local_block_start(code, ins, info, context)
      end

      def visit_local_block_end(code, ins, info, context)
      end

      def visit_getlocal(code, ins, info, context)
      end

      def visit_setlocal(code, ins, info, context)
      end

      # getspecial
      # setspecial

      def visit_getdynamic(code, ins, info, context)
      end

      def visit_setdynamic(code, ins, info, context)
      end

      # getinstancevariable
      # setinstancevariable
      # getclassvariable
      # setclassvariable
      
      def visit_getconstant(code, ins, info, context)
      end

      def visit_setconstant(code, ins, info, context)
      end

      # getglobal
      # setglobal
      
      def visit_putnil(code, ins, info, context)
      end

      def visit_putself(code, ins, info, context)
      end
      
      def visit_putobject(code, ins, info, context)
      end

      def visit_putspecialobject(code, ins, info, context)
      end

      def visit_putiseq(code, ins, info, context)
      end

      def visit_putstring(code, ins, info, context)
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

      def visit_pop(code, ins, info, context)
      end

      def visit_dup(code, ins, info, context)
      end

      def visit_dupn(code, ins, info, context)
      end

      def visit_swap(code, ins, info, context)
      end

      # reput
      
      def visit_topn(code, ins, info, context)
      end

      def visit_setn(code, ins, info, context)
      end

      # adjuststack
      # defined

      def visit_trace(code, ins, info, context)
      end

      def visit_defineclass(code, ins, info, context)
      end

      def visit_send(code, ins, info, context)
      end

      def visit_invokesuper(code, ins, info, context)
      end

      def visit_invokeblock(code, ins, info, context)
      end

      def visit_leave(code, ins, info, context)
      end
      
      def visit_throw(code, ins, info, context)
      end

      def visit_jump(code, ins, info, context)
      end

      def visit_branchif(code, ins, info, context)
      end

      def visit_branchunless(code, ins, info, context)
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

