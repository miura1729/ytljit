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

        def gen_boxing(context)
          context
        end

        def gen_unboxing(context)
          p "inboxing"
          context
        end
      end

      module FloatTypeUnboxedCodeGen
        include AbsArch

        def gen_boxing(context)
          asm = context.assembler
          val = context.ret_reg
          vnode = context.ret_node
          context.start_using_reg(TMPR2)
          context.start_using_reg(TMPR3)
          context.start_using_reg(FUNC_FLOAT_ARG[0])
          rbfloatnew = OpMemAddress.new(address_of("rb_float_new"))
          asm.with_retry do
            asm.mov(FUNC_FLOAT_ARG[0], val)
            asm.call_with_arg(rbfloatnew, 1)
          end
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
          context.start_using_reg(TMPR2)
          context.start_using_reg(TMPR3)
          context.start_using_reg(FUNC_ARG[0])
          rbarydup = OpMemAddress.new(address_of("rb_ary_dup"))
          asm.with_retry do
            asm.mov(FUNC_ARG[0], val)
            asm.call_with_arg(rbarydup, 1)
          end
          context.end_using_reg(FUNC_ARG[0])
          context.end_using_reg(TMPR3)
          context.end_using_reg(TMPR2)
          context.ret_reg = RETR

          context
        end

        def ==(other)
          other.is_a?(self.class) and
          self.class == other.class and
          @element_type == other.element_type
        end
      end

      module StringTypeBoxedCodeGen
        include AbsArch

        def gen_copy(context)
          asm = context.assembler
          val = context.ret_reg
          context.start_using_reg(TMPR2)
          context.start_using_reg(TMPR3)
          context.start_using_reg(FUNC_ARG[0])
          rbstrresurrect = OpMemAddress.new(address_of("rb_str_resurrect"))
          asm.with_retry do
            asm.mov(FUNC_ARG[0], val)
            asm.call_with_arg(rbstrresurrect, 1)
          end
          context.end_using_reg(FUNC_ARG[0])
          context.end_using_reg(TMPR3)
          context.end_using_reg(TMPR2)
          context.ret_reg = RETR

          context
        end
      end

      module ArrayTypeUnboxedCodeGen
        def have_element?
          true
        end
      end
    end
  end
end
