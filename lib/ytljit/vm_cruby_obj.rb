module YTLJit
  module VM
    module Node
      class CRubyInstanceVarRefNode<InstanceVarRefNode
        include TypeListWithoutSignature

        def initialize(parent, name)
          super
          @current_frame_info = search_frame_info
        end

        def compile_main(context)
          slfoff = @current_frame_info.offset_arg(2, BPR)
          ivid = ((@name.object_id << 1) / InternalRubyType::RObject.size)
          ivarget = OpMemAddress.new(address_of("rb_ivar_get"))
          context.start_using_reg(FUNC_ARG[0])
          context.start_using_reg(FUNC_ARG[1])
          asm = context.assembler
          asm.with_retry do
            asm.mov(FUNC_ARG[0], slfoff)
            asm.mov(FUNC_ARG[1], ivid)
            asm.call_with_arg(ivarget, 2)
          end
          context.end_using_reg(FUNC_ARG[1])
          context.end_using_reg(FUNC_ARG[0])
          
          context.ret_reg = RETR
          context.ret_node = self
          context
        end
      end

      class CRubyInstanceVarAssignNode<InstanceVarAssignNode
        include TypeListWithoutSignature

        def initialize(parent, name, val)
          super
          @current_frame_info = search_frame_info
        end

        def compile_main(context)
          slfoff = @current_frame_info.offset_arg(2, BPR)
          ivid = ((@name.object_id << 1) / InternalRubyType::RObject.size)
          ivarset = OpMemAddress.new(address_of("rb_ivar_set"))
          context = @val.compile(context)
          rtype = @val.decide_type_once(context.to_signature)
          context = rtype.gen_boxing(context)

          context.start_using_reg(FUNC_ARG[0])
          context.start_using_reg(FUNC_ARG[1])
          context.start_using_reg(FUNC_ARG[2])
          asm = context.assembler
          asm.with_retry do
            asm.push(TMPR2)
            asm.mov(TMPR2, context.ret_reg)
            asm.mov(FUNC_ARG[0], slfoff)
            asm.mov(FUNC_ARG[1], ivid)
            asm.mov(FUNC_ARG[2], TMPR2)
            asm.call_with_arg(ivarset, 3)
            asm.pop(TMPR2)
          end
          context.end_using_reg(FUNC_ARG[2])
          context.end_using_reg(FUNC_ARG[1])
          context.end_using_reg(FUNC_ARG[0])
          
          context.ret_reg = RETR
          context.ret_node = self
          @body.compile(context)
        end
      end
    end

    module YARVTranslatorCRubyObjectMixin
      include Node

      def visit_getinstancevariable(code, ins, context)
        curnode = context.current_node
        node = CRubyInstanceVarRefNode.new(curnode, ins[1])
        node.debug_info = context.debug_info
        context.expstack.push node
      end

      def visit_setinstancevariable(code, ins, context)
        val = context.expstack.pop
        curnode = context.current_node
        node = CRubyInstanceVarAssignNode.new(curnode, ins[1], val)
        node.debug_info = context.debug_info
        if context.expstack[-1] == val then
          context.expstack[-1] = CRubyInstanceVarRefNode.new(curnode, ins[1])
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

      
