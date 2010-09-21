module YTLJit
  module VM
    module TypeCodeGen
      module DefaultTypeCodeGen
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
    end
  end
end
