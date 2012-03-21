module YTLJit
  module VM
    module Node
      class CRubyInstanceVarRefNode<InstanceVarRefNode
        include TypeListWithoutSignature
        include CommonCodeGen
        include UnboxedArrayUtil

        def initialize(parent, name, mnode)
          super
          @current_frame_info = search_frame_info_without_inline
        end

        def compile_main(context)
          slfoff = @current_frame_info.offset_arg(2, BPR)
          cursig = context.to_signature
          compile_main_aux(context, slfoff, cursig[2])
        end

        def compile_main_aux(context, slfcont, slftype)
          mivl = @class_top.end_nodes[0].modified_instance_var.keys
          off = mivl.index(@name)
          cursig = context.to_signature
          asm = context.assembler

          if !slftype.boxed then
            context.start_using_reg(TMPR2)
            asm.with_retry do
              asm.mov(TMPR2, slfcont)
            end
            context = gen_ref_element(context, nil, off)
            context.end_using_reg(TMPR2)
            rtype = decide_type_once(cursig)
            if rtype.ruby_type == Float and !rtype.boxed then
              asm.with_retry do
                asm.mov(XMM0, context.ret_reg)
              end
              context.ret_reg = XMM0
            else
              asm.with_retry do
                asm.mov(RETR, context.ret_reg)
              end
              context.ret_reg = RETR
            end
            return context
          end

          addr = lambda {
            a = address_of("ytl_ivar_get_boxing")
            $symbol_table[a] = "ytl_ivar_get_boxing"
            a
          }
          ivarget = OpVarMemAddress.new(addr)
          context.start_arg_reg
          asm.with_retry do
            asm.mov(FUNC_ARG[0], slfcont)
            asm.mov(FUNC_ARG[1], off)
          end
          context = gen_save_thepr(context)
          context = gen_call(context, ivarget, 2)

          context.end_arg_reg
          context.ret_reg = RETR
          context.ret_node = self
          decide_type_once(cursig)
          if !@type.boxed then 
            context = @type.to_box.gen_unboxing(context)
          end
          context
        end
      end

      class CRubyInstanceVarAssignNode<InstanceVarAssignNode
        include TypeListWithoutSignature
        include CommonCodeGen
        include UnboxedArrayUtil

        def initialize(parent, name, mnode, val)
          super
          @current_frame_info = search_frame_info_without_inline
        end

        def compile_main(context)
          slfoff = @current_frame_info.offset_arg(2, BPR)
          cursig = context.to_signature
          compile_main_aux(context, slfoff, cursig[2], @val, @body)
        end

        def compile_main_aux(context, slfcont, slftype, val, body)
          cursig = context.to_signature
          mivl = @class_top.end_nodes[0].modified_instance_var.keys
          off = mivl.index(@name)
          rtype = val.decide_type_once(cursig)

          if !slftype.boxed then
            asm = context.assembler
            asm.with_retry do
              asm.mov(TMPR2, slfcont)
            end
            context = gen_set_element(context, nil, off, val)
            if body then
              return body.compile(context)
            else
              return context
            end
          end

          addr = lambda {
            a = address_of("ytl_ivar_set_boxing")
            $symbol_table[a] = "ytl_ivar_set_boxing"
            a
          }
          ivarset = OpVarMemAddress.new(addr)

          context.start_using_reg(TMPR2)
          context.start_arg_reg
          asm = context.assembler
          asm.with_retry do
            asm.mov(FUNC_ARG[0], slfcont)
          end

          context = val.compile(context)
          context = rtype.gen_boxing(context)

          asm.with_retry do
            asm.mov(TMPR2, context.ret_reg)
            asm.mov(FUNC_ARG[1], off)
            asm.mov(FUNC_ARG[2], TMPR2)
          end
          context = gen_save_thepr(context)
          context = gen_call(context, ivarset, 3)

          context.end_arg_reg
          context.end_using_reg(TMPR2)
          
          context.ret_reg = RETR
          context.ret_node = self
          if body then
            body.compile(context)
          else
            context
          end
        end
      end
    end

    module YARVTranslatorCRubyObjectMixin
      include Node

      def visit_getinstancevariable(code, ins, context)
        context.macro_method = false
        curnode = context.current_node
        mnode = context.current_method_name
        node = CRubyInstanceVarRefNode.new(curnode, ins[1], mnode)
        node.debug_info = context.debug_info
        context.expstack.push node
      end

      def visit_setinstancevariable(code, ins, context)
        context.macro_method = false
        val = context.expstack.pop
        curnode = context.current_node
        mnode = context.current_method_name
        node = CRubyInstanceVarAssignNode.new(curnode, ins[1], mnode, val)
        node.debug_info = context.debug_info
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

      
