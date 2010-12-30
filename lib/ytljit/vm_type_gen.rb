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
          context.start_using_reg(TMPR3)
          context.start_using_reg(FUNC_FLOAT_ARG[0])
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
          context.end_using_reg(FUNC_FLOAT_ARG[0])
          context.end_using_reg(TMPR3)
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
          context.start_using_reg(TMPR2)
          context.start_using_reg(TMPR3)
          context.start_using_reg(FUNC_ARG[0])
          rbarydup = OpMemAddress.new(address_of("rb_ary_dup"))
          asm.with_retry do
            asm.mov(FUNC_ARG[0], val)
          end
          context.set_reg_content(FUNC_ARG[0].dst_opecode, vnode)
          context = gen_call(context, rbarydup, 1, vnode)
          context.end_using_reg(FUNC_ARG[0])
          context.end_using_reg(TMPR3)
          context.end_using_reg(TMPR2)
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
          other.is_a?(self.class) and
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
          context.start_using_reg(TMPR3)
          context.start_using_reg(FUNC_ARG[0])
          rbstrresurrect = OpMemAddress.new(address_of("rb_str_resurrect"))
          asm.with_retry do
            asm.mov(FUNC_ARG[0], val)
          end
          context.set_reg_content(FUNC_ARG[0].dst_opecode, vnode)
          context = gen_call(context, rbstrresurrect, 1, vnode)
          context.end_using_reg(FUNC_ARG[0])
          context.end_using_reg(TMPR3)
          context.end_using_reg(TMPR2)
          context.ret_reg = RETR

          context
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
