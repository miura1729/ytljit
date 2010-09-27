module YTLJit
  module VM
    module TypeCodeGen
      module DefaultTypeCodeGen
        def instance
          self
        end

        def init_type
        end

        def gen_boxing(context)
          context
        end

        def gen_unboxing(context)
          context
        end
      end

      module FixnumTypeUnboxedCodeGen
        include AbsArch

        def gen_boxing(context)
          asm = context.assembler
          val = context.ret_reg
          vnode = context.ret_node
          context.start_using_reg(TMPR)
          asm.with_retry do
            if val != TMPR then
              asm.mov(TMPR, val)
            end
            asm.add(TMPR, TMPR)
            asm.add(TMPR, OpImmidiate8.new(1))
          end

          context.set_reg_content(TMPR, vnode)
          context.ret_reg = TMPR
          context.ret_node = self
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
          context.start_using_reg(TMPR)
          asm.with_retry do
            if val != TMPR then
              asm.mov(TMPR, val)
            end
            asm.sar(TMPR)
          end
          context.set_reg_content(TMPR, vnode)
          context.ret_node = self
          context.ret_reg = TMPR
          context
        end
      end

      module FloatTypeBoxedCodeGen
        include AbsArch

        def gen_boxing(context)
          p "boxingaaa"
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
          context.start_using_reg(FUNC_FLOAT_ARG[0])
          rbfloatnew = OpMemAddress.new(address_of("rb_float_new"))
          asm.with_retry do
            asm.mov(FUNC_FLOAT_ARG[0], val)
            asm.call(rbfloatnew)
          end
          context.end_using_reg(FUNC_FLOAT_ARG[0])
          context.ret_reg = RETR
          context
        end

        def gen_unboxing(context)
          p "unboxing"
          context
        end
      end
    end
  end
end
