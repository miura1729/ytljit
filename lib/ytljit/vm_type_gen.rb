module YTLJit
  module VM
    module TypeCodeGen
      module DefaultTypeCodeGen
        def instance
          self
        end

        def init_type
        end

        def have_element?
          false
        end

        def gen_boxing(context)
          context
        end

        def gen_unboxing(context)
          context
        end

        def gen_copy(context)
          context
        end

        def inspect
          "{ #{boxed ? "BOXED" : "UNBOXED"} #{@ruby_type}}"
        end
      end

      module FixnumTypeUnboxedCodeGen
        include AbsArch
        include CommonCodeGen

        def gen_boxing(context)
          asm = context.assembler
          val = context.ret_reg
          vnode = context.ret_node
          asm.with_retry do
            if val != TMPR then
              asm.mov(TMPR, val)
            end
            asm.add(TMPR, TMPR)
            asm.add(TMPR, OpImmidiate8.new(1))
          end

          context.set_reg_content(TMPR, vnode)
          context.ret_reg = TMPR
          context
        end

        def gen_unboxing(context)
          context
        end
      end

      module FixnumTypeBoxedCodeGen
        include AbsArch
        include CommonCodeGen

        def gen_boxing(context)
          context
        end
        
        def gen_unboxing(context)
          asm = context.assembler
          val = context.ret_reg
          vnode = context.ret_node
          asm.with_retry do
            if val != TMPR then
              asm.mov(TMPR, val)
            end
            asm.sar(TMPR)
          end
          context.set_reg_content(TMPR, vnode)
          context.ret_reg = TMPR
          context
        end
      end

      module FloatTypeBoxedCodeGen
        include AbsArch
        include CommonCodeGen

        def gen_boxing(context)
          context
        end

        def gen_unboxing(context)
          asm = context.assembler
          fobj = TypedData.new(InternalRubyType::RFloat, context.ret_reg)
          asm.with_retry do
            asm.movsd(XMM0, fobj[:float_value])
          end

          context.ret_reg = XMM0
          context
        end
      end

      module FloatTypeUnboxedCodeGen
        include AbsArch
        include CommonCodeGen

        def gen_boxing(context)
          asm = context.assembler
          val = context.ret_reg
          vnode = context.ret_node
          context.start_using_reg(TMPR2)
          context.start_arg_reg(FUNC_FLOAT_ARG)
          context.start_arg_reg
          rbfloatnew = OpMemAddress.new(address_of("rb_float_new"))
=begin
          # This is sample of backtrace
          sh = OpMemAddress.new(address_of("ytl_step_handler"))
          context = gen_call(context, sh, 0, vnode)
=end
          asm.with_retry do
            asm.mov(FUNC_FLOAT_ARG[0], val)
          end
          context.set_reg_content(FUNC_FLOAT_ARG[0].dst_opecode, vnode)
          context = gen_call(context, rbfloatnew, 1, vnode)
          context.end_arg_reg
          context.end_arg_reg(FUNC_FLOAT_ARG)
#          context.end_using_reg(TMPR3)
          context.end_using_reg(TMPR2)
          context.ret_reg = RETR
          context
        end

        def gen_unboxing(context)
          context
        end
      end

      module ArrayTypeBoxedCodeGen
        include AbsArch
        include CommonCodeGen

        def instance
          ni = self.dup
          ni.instance_eval { extend ArrayTypeBoxedCodeGen }
          ni.init
          ni
        end

        def init
          @element_type = nil
        end

        attr_accessor :element_type

        def have_element?
          true
        end

        def gen_copy(context)
          asm = context.assembler
          val = context.ret_reg
          vnode = context.ret_node
          context.start_using_reg(TMPR3)
          context.start_arg_reg
          rbarydup = OpMemAddress.new(address_of("rb_ary_dup"))
          asm.with_retry do
            asm.mov(FUNC_ARG[0], val)
          end
          context.set_reg_content(FUNC_ARG[0].dst_opecode, vnode)
          context = gen_call(context, rbarydup, 1, vnode)
          context.end_arg_reg
          context.end_using_reg(TMPR3)
          context.ret_reg = RETR

          context
        end

        def ==(other)
          if other then
            oc = other.ruby_type
            sc = self.ruby_type
            sc == oc and
              @element_type == other.element_type
          else
            false
          end
        end

        def eql?(other)
          self.class == other.class and
          @element_type == other.element_type
        end
      end

      module StringTypeBoxedCodeGen
        include AbsArch
        include CommonCodeGen

        def gen_copy(context)
          asm = context.assembler
          val = context.ret_reg
          vnode = context.ret_node
          context.start_using_reg(TMPR2)
          context.start_arg_reg
          rbstrresurrect = OpMemAddress.new(address_of("rb_str_resurrect"))
          asm.with_retry do
            asm.mov(FUNC_ARG[0], val)
          end
          context.set_reg_content(FUNC_ARG[0].dst_opecode, vnode)
          context = gen_call(context, rbstrresurrect, 1, vnode)
          context.end_arg_reg
          context.end_using_reg(TMPR2)
          context.ret_reg = RETR

          context
        end
      end

      module RangeTypeUnboxedCodeGen
        include AbsArch
        include CommonCodeGen

        def instance
          ni = self.dup
          ni.instance_eval { extend RangeTypeUnboxedCodeGen }
          ni.init
          ni
        end

        def init
          @args = nil
        end

        attr_accessor :args

        def gen_boxing(context)
          rtype = args[0].decide_type_once(context.to_signature)

          base = context.ret_reg
          rbrangenew = OpMemAddress.new(address_of("rb_range_new"))
          begoff = OpIndirect.new(TMPR2, 0)
          endoff = OpIndirect.new(TMPR2, AsmType::MACHINE_WORD.size)
          excoff = OpIndirect.new(TMPR2, AsmType::MACHINE_WORD.size * 2)
 
          context.start_using_reg(TMPR2)
          context.start_arg_reg
          asm = context.assembler
          asm.with_retry do
            asm.mov(TMPR2, base)
          end

          context.ret_reg = begoff
          context = rtype.gen_boxing(context)
          asm.with_retry do
            asm.mov(FUNC_ARG[0], context.ret_reg)
          end

          context.ret_reg = endoff
          context = rtype.gen_boxing(context)
          asm.with_retry do
            asm.mov(FUNC_ARG[1], context.ret_reg)
          end

          asm.with_retry do
            asm.mov(FUNC_ARG[2], excoff)
            asm.call_with_arg(rbrangenew, 3)
          end

          context.end_arg_reg
          context.end_using_reg(TMPR2)
          context.ret_reg = RETR
          context
        end
        
        def ==(other)
          self.class == other.class and
            @args == other.args
        end
      end

      module ArrayTypeUnboxedCodeGen
        include AbsArch
        include CommonCodeGen

        def have_element?
          true
        end
      end
    end
  end
end
