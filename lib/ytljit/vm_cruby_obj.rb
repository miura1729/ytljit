module YTLJit
  module VM
    module Node
      class CRubyInstanceVarRefNode<InstanceVarRefNode
        include TypeListWithoutSignature
        include CommonCodeGen

        def initialize(parent, name, mnode)
          super
          @current_frame_info = search_frame_info
        end

        def compile_main(context)
          slfoff = @current_frame_info.offset_arg(2, BPR)
          mivl = @class_top.end_nodes[0].modified_instance_var.keys
          off = mivl.index(@name)
          addr = lambda {
            address_of("ytl_ivar_get_boxing")
          }
          ivarget = OpVarMemAddress.new(addr)
          context.start_arg_reg
          asm = context.assembler
          asm.with_retry do
            asm.mov(FUNC_ARG[0], slfoff)
            asm.mov(FUNC_ARG[1], off)
          end
          context = gen_save_thepr(context)
          asm.with_retry do
            asm.call_with_arg(ivarget, 2)
          end

          context.end_arg_reg
          context.ret_reg = RETR
          context.ret_node = self
          decide_type_once(context.to_signature)
          if !@type.boxed then 
            context = @type.to_box.gen_unboxing(context)
          end
          context
        end
      end

      class CRubyInstanceVarAssignNode<InstanceVarAssignNode
        include TypeListWithoutSignature
        include CommonCodeGen

        def initialize(parent, name, mnode, val)
          super
          @current_frame_info = search_frame_info
        end

        def compile_main(context)
          slfoff = @current_frame_info.offset_arg(2, BPR)
          mivl = @class_top.end_nodes[0].modified_instance_var.keys
          off = mivl.index(@name)
          addr = lambda {
            address_of("ytl_ivar_set_boxing")
          }
          ivarset = OpVarMemAddress.new(addr)
          context = @val.compile(context)
          rtype = @val.decide_type_once(context.to_signature)
          context = rtype.gen_boxing(context)

          context.start_arg_reg
          asm = context.assembler
          asm.with_retry do
            asm.push(TMPR2)
            asm.mov(TMPR2, context.ret_reg)
            asm.mov(FUNC_ARG[0], slfoff)
            asm.mov(FUNC_ARG[1], off)
            asm.mov(FUNC_ARG[2], TMPR2)
          end
          context = gen_save_thepr(context)
          asm.with_retry do
            asm.call_with_arg(ivarset, 3)
            asm.pop(TMPR2)
          end
          context.end_arg_reg
          
          context.ret_reg = RETR
          context.ret_node = self
          @body.compile(context)
        end
      end
    end

    module YARVTranslatorCRubyObjectMixin
      include Node

      def visit_getinstancevariable(code, ins, context)
        context.macro_method = false
        curnode = context.current_node
        mnode = context.current_method_node
        node = CRubyInstanceVarRefNode.new(curnode, ins[1], mnode)
        node.debug_info = context.debug_info
        context.expstack.push node
      end

      def visit_setinstancevariable(code, ins, context)
        context.macro_method = false
        val = context.expstack.pop
        curnode = context.current_node
        mnode = context.current_method_node
        node = CRubyInstanceVarAssignNode.new(curnode, ins[1], mnode, val)
        node.debug_info = context.debug_info
        if context.expstack[-1] == val then
          ivr = CRubyInstanceVarRefNode.new(curnode, ins[1], mnode)
          context.expstack[-1] = ivr
        end
        curnode.body = node
        context.current_node = node
      end
    end

    class YARVTranslatorCRubyObject<YARVTranslatorBase
      include YARVTranslatorSimpleMixin
      include YARVTranslatorCRubyObjectMixin
    end
  end
end

      
