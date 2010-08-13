module YTLJit
  module VM
    module Node
      class TISelfRefNode<SelfRefNode
        def initialize(parent)
          super(parent)
        end

        def compile_main(context)
          slf = context.slf
          slfval = lambda { slf.address }
          slfadd = OpVarImmdiateAddress.new(slfval)
          asm = context.assembler
          asm.with_retry do
            asm.mov(RETR, slfadd)
          end

          context.ret_reg = RETR
          context
        end
      end

      class TIInstanceVarRefNode<InstanceVarRefNode
        def initialize(parent, name)
          super(parent, name)
        end

        def compile_main(context)
          slf = context.slf
          ivval = lambda { slf.instance_var_address_of(@name) }
          ivadd = OpVarImmidiateAddress.new(ivval)
          asm = context.assembler
          asm.with_retry do
            asm.mov(TMPR, ivadd)
            asm.mov(RETR, INDIRECT_TMPR)
          end

          context.ret_reg = RETR
          context
        end
      end

      class TIInstanceVarAssignNode<InstanceVarAssignNode
        def initialize(parent, name, val)
          super(parent, name, val)
        end

        def compile_main(context)
          context = @val.compile(context)
          valr = context.ret_reg
          slf = context.slf
          ivval = lambda { slf.instance_var_address_of(@name) }
          ivadd = OpVarImmdiateAddress.new(ivval)
          asm = context.assembler
          asm.with_retry do
            asm.mov(TMPR, ivadd)
            asm.mov(INDIRECT_TMPR, valr)
          end

          context.ret_reg = RETR
          context
        end
      end
    end

    module YARVTranslatorTypeInferenceMixin
      include Node

      def initialize(parent)
        super(parent)
      end

      def visit_putself(code, ins, context)
        curnode = context.current_node
        nnode = TISelfRefNode.new(curnode)
        context.expstack.push nnode
      end

      def visit_getinstancevariable(code, ins, context)
        curnode = context.current_node
        node = TIInstanceVarRefNode.new(curnode, ins[1])
        context.expstack.push node
      end

      def visit_setinstancevariable(code, ins, context)
        val = context.expstack.pop
        curnode = context.current_node
        node = TiInstanceVarAssignNode.new(curnode, ins[1], val)
        curnode.body = node
        context.current_node = node
      end
    end

    class YARVTranslatorTypeInference<YARVTranslatorSimple
      include YARVTranslatorTypeInferenceMixin
    end
  end
end
