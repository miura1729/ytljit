module YTLJit
  module VM
    module Node
      class TISelfRefNode<SelfRefNode
        def initialize(parent, slf)
          super(parent)
          @slf = slf
        end

        def compile_main(context)
          slfadd = OpImmidiateAddress.new(@slf.address)
          asm = context.assembler
          asm.with_retry do
            asm.mov(RETR, slfadd)
          end

          context.ret_reg = RETR
          context
        end
      end

      class TIInstenceVarRefNode<InstanceVarRefNode
        def compile_main(context)
        end
      end

      class TIInstanceAssignNode<InstanceAssignNode
        def compile_main(context)
        end
      end
    end

    module YARVTranslatorTypeInferenceMixin
      def visit_putself(code, ins, context)
        curnode = context.current_node
        nnode = TISelfRefNode.new(curnode, context.slf)
        context.expstack.push nnode
      end
    end

    class YARVTranslatorTypeInference<YARVTranslatorBase
      include YARVTranslatorSimpleMixin
      include YARVTranslatorTypeInferenceMixin
    end
  end
end
