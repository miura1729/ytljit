module YTLJit

=begin
  Stack layout (on stack frame)


Hi     |  |Argn                   |   |
       |  |   :                   |   |
       |  |Arg3(exception status) |   |
       |  |Arg2(block pointer)    |   |
       |  |Arg1(parent frame)     |  -+
       |  |Arg0(self)             |
       |  |Return Address         |
       +- |old bp                 | <-+
          |old bp on stack        |  -+
    EBP-> |Local Vars1            |   
          |                       |   
          |                       |   
          |Local Varsn            |   
          |Pointer to Env         |   
   SP ->  |                       |
          |                       |
LO        


  Stack layout (on heap frame)


Hi     |  |Arg0(self)             |   |
       |  |Arg1(parent frame)     |  -+
       |  |Arg2(block pointer)    |
       |  |Arg3(exception status) |
       |  |   :                   |
       |  |Arg n                  |
       |  |Return Address         |
       +- |old bp                 |  <---+
          |Pointer to Env         |  -+  |
   SP ->  |                       |   |  |
LO        |                       |   |  |
                                      |  |
                                      |  |
       +- |                       |   |  |
       |  |free func              |   |  |
       |  |mark func              |   |  |
       |  |T_DATA                 | <-+  |                                      
       |                                 |
       |                                 |
       |  |Arg n                  |      |
       |  |   :                   |      |
       |  |Arg3(exception status) |      |
       |  |Arg2(block pointer)    |      |
       |  |Arg1(parent frame)     |      |
       |  |Arg0(self)             |      |   
       |  |Not used(reserved)     |      |
       |  |old bp on stack        | -----+
    EBP-> |Local Vars1            |   
       |  |                       |   
       |  |                       |   
       +->|Local Varsn            |   

  enter procedure
    push EBP
    SP -> EBP
    allocate frame (stack or heap)    
    Copy arguments if allocate frame on heap
    store EBP on the top of frame
    Address of top of frame -> EBP
 
  leave procedure
    Dereference of EBP -> ESP
    pop EBP
    ret

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
        def initialize(parent, args, name = nil)
          super()
          @arg_list = args
          @name = name
          @body = []
          @parent = parent
          @frame_size = nil
        end

        def add_body(node)
          @body.push node
        end

        def to_asmcode(context)
          context = gen_method_prologe(context)
          @body.each do |ele|
            ele.to_asmcode(context)
          end
        end
      end

      # End of method definition
      class MethodEndNode<BaseNode
        def initialize
          super
          @parent_method = nil
        end

        def to_asmcode(context)
          context = gen_method_prologe(context)
          curcs = context.code_space
          curas = Assembler.new(curcs)
          curas.with_retry do
            curas.ret
          end
        end
      end

      # if statement
      class IfNode<HaveChildlen
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
          curcs = context.code_space
          curas = Assembler.new(curcs)
          elsecs = @else_cs
          contcs = @cont_cs

          curas.with_retry do
            curas.and(context.ret_reg, OpImmdiate(~4))
            curas.jn(elsecs.var_base_address)
          end
          context = tpart.to_asmcode(context)
          curcs = context.code_space
          curcs.with_retry do
            curcs.jmp(contcs.var_base_address)
          end

          context.code_space = elsecs
          curcs = context.code_space
          context = epart.to_asmcode(context)
          curcs.with_retry do
            curcs.jmp(contcs.var_base_address)
          end
          context.code_space = context
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

