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

        def compile(context)
          context = gen_method_prologe(context)
          context = @body.compile(context)
          context
        end
      end

      # End of method definition
      class MethodEndNode<BaseNode
        include MethodEndCodeGen

        def initialize
          super()
          @parent_method = nil
        end

        def compile(context)
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

        def compile(context)
          context = @cond.compile(context)
          elsecs = @else_cs
          contcs = @cont_cs

          curas = context.assembler
          curas.with_retry do
            curas.and(context.ret_reg, OpImmdiate(~4))
            curas.jn(elsecs.var_base_address)
          end

          context = tpart.compile(context)
          tretr = context.ret_reg
          tas = context.assembler

          context.add_code_space(code_space)
          context = epart.compile(context)
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

      # Call methodes
      class CallNode<HaveChildlen
        @@current_node = nil
        
        def self.nodes
          @@current_node
        end

        def initialize
          super()
          @arguments = []
          @func = nil
          @var_return_address = nil
          @next_node = @@current_node
          @@current_node = self
        end

        attr_accrssor :func
        attr_accrssor :arguments
        attr          :var_return_address
        attr          :next_node

        def compile(context)
          @arguments.each_with_index do |arg, i|
            context = arg.compile(context)
            casm = context.assembler
            casm.with_retry do 
              casm.mov(FUNC_ARG[i], context.ret_reg)
            end
          end
          context = @func.compile(context)
          fnc = context.ret_reg
          casm = context.assembler
          casm.with_retry do 
            casm.call(fnc)
          end
          off = casm.offset
          @var_return_address = casm.output_stream.var_base_address(off)

          context
        end
      end

      # Literal
      class LiteralNode<BaseNode
        def initialize(obj)
          super()
          @object = obj
        end

        def compile(context)
          case @objct
          when Fixnum
            context.ret_reg = OpImmdiateMachineWord.new(@object)
          else
            context.ret_reg = OpImmdiateAddress.new(address_of(@object))
          end

          context
        end
      end

      # Variable Common
      class VariableCommonNode<BaseNode
      end

      # Local Variable
      class LocalVarNode<VariableCommonNode
        include LocalVarNodeCodeGen

        def initialize(offset, depth)
          super()
          @offset = offset
          @depth = depth
        end

        def compile(context)
          context = gen_pursue_parent_function(context, @depth)
          
        end
      end

      # Instance Variable
      class InstanceVarNode<VariableCommonNode
      end

      # Define and assign local variable
      class AssignNode<HaveChildlen
      end

      # Reference Register
      class RefRegister
      end
    end
  end
end

