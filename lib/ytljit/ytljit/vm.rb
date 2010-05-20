module YTLJit

=begin
Typical struct of node

def fact(x)
  if x == 0 then
    return 1
  else
    return x * fact(x - 1)
  end
end


MethodTopNode
  name -> "fact"     
  body  
   |
IfNode
  epart------------------+
  tpart----------------+ |
  cond                 | |
   |                   | |
CallNode               | |
  func -> ==           | |
  arg[0]------------+  | |
  arg[1]            |  | |
   |                |  | |
LiteralNode         |  | |
  value -> 0        |  | |
                    |  | |
    +---------------+  | |
    |                  | |
LocalVarNode           | |
  offset -> 0          | |
  depth -> 0           | |
                       | |
    +------------------+ |
    |                    |
MethodEndNode            |
  value                  |
    |                    |
LiteralNode              |
  value -> 0             |
                         |
    +--------------------+
    |
MethodEndNode
  value
    |
CallNode
   func -> *
   arg[0] --------------+
   arg[1]               |
    |                   |
CallNode                |
   func -> fact         |
   arg[0]               |
    |                   |
CallNode                |
   func -> -            |
   arg[0] -----+        |
   arg[1]      |        |
    |          |        |
LiteralNode    |        |
  value -> 0   |        |
               |        |
    +----------+        |
    |                   |
LocalVarNode            |
  offset -> 0           |
  depth -> 0            |
                        |
    +-------------------+
    |
LocalVarNode            
  offset -> 0           
  depth -> 0            

=end

  module VM
    # Expression of VM is a set of Nodes
    module Node
      class BaseNode
        def initialize
          cs = CodeSpace.new
          asm = Assembler.new(cs)
          asm.with_retry do
            asm.ret
          end
          @type_inference_proc = cs
          @type_cache = nil

          @parent = nil
        end
        attr_accessor :parent

        def inference_type
          cs = @type_inference_proc
          cs.call(cs.base_address)
        end

        def gen_type_inference_proc(code)
          
        end

        # dummy methods
        def add_modified_var(var); end
      end

      class HaveChildlen<BaseNode
        def initialize
          super()
          @modified_var = []
        end

        def add_modified_var(lvar)
          unless @modified_var.include?(lvar)
            @modified_var.push lvar
          end
          @parent.add_modified_var(lvar)
        end
      end

      # Top of method definition
      class MethodTopNode<HaveChildlen
        include MethodTopCodeGen
        def initialize(parent, args, name = nil)
          super()
          @arg_list = args
          @name = name
          @body = nil
          @parent = parent
          @frame_size = nil
        end

        def to_asmcode(context)
          context = gen_method_prologe(context)
          context = @body.to_asmcode(context)
          context
        end
      end

      # End of method definition
      class MethodEndNode<BaseNode
        include MethodEndCodeGen

        def initialize
          super
          @parent_method = nil
        end

        def to_asmcode(context)
          context = gen_method_prologe(context)
          curas = context.assembler
          curas.with_retry do
            curas.ret
          end
          context
        end
      end

      # if statement
      class IfNode<HaveChildlen
        include IfNodeCodeGen

        def initialize(cond, tpart, epart)
          super()
          @cond = cond
          @tpart = tpart
          @epart = epart

          @else_cs = CodeSpace.new
          @cont_cs = CodeSpace.new
        end

        def to_asmcode(context)
          context = @cond.to_asmcode(context)
          elsecs = @else_cs
          contcs = @cont_cs

          curas = context.assembler
          curas.with_retry do
            curas.and(context.ret_reg, OpImmdiate(~4))
            curas.jn(elsecs.var_base_address)
          end

          context = tpart.to_asmcode(context)
          tretr = context.ret_reg
          tas = context.assembler

          context.add_code_space(code_space)
          context = epart.to_asmcode(context)
          eretr = context.ret_reg
          eas = context.assembler

          tas.with_retry do
            unify_retreg_tpart(tretr, eretr, tas)
            tas.jmp(contcs.var_base_address)
          end

          eas.with_retry do
            unify_retreg_epart(tretr, eretr, eas)
            eas.jmp(contcs.var_base_address)
          end

          context.add_code_space(contcs)
          cas = context.assembler
          cas.with_retry do
            unify_retreg_cont(tretr, eretr, cas)
          end
          context
        end
      end

      # Guard (type information holder and type checking of tree)
      class GuardNode<HaveChildlen
      end

      # Holder of Nodes Assign. These assignes execute parallel potencially.
      class LetNode<HaveChildlen
      end

      # Define and assign local variable
      class AssignNode<HaveChildlen
      end

      # Call methodes
      class CallNode<HaveChildlen
        def initialize
          super()
          @arguments = []
          @func = nil
        end

        attr_accrssor :func
        attr_accrssor :arguments

        def to_asmcode(context)
          @arguments.each_with_index do |arg, i|
            context = arg.to_asmcode(context)
            casm = context.assembler
            casm.with_retry do 
              casm.mov(FUNC_ARG[i], context.ret_reg)
            end
          end
          context = @func.to_asmcode(context)
          fnc = context.ret_reg
          context
        end
      end

      # Literal
      class LiteralNode<BaseNode
      end

      # Variable Common
      class VariableCommonNode<BaseNode
      end

      # Local Variable
      class LocalVarNode<VariableCommonNode
      end

      # Instance Variable
      class InstanceVarNode<VariableCommonNode
      end

      # Reference Register
      class RefRegister
      end
    end
  end
end

