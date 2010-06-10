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
LocalFrameInfo
  frame       -- infomation of frame (access via insptance methodes)
  body
   |
GuardInfo
  type_list -> [[a, Fixnum], [v, Fixnum]], [[a, Float], [v, Fixnum]] ...
  body
       # Compile each element of type_list.
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
        include Inspect
        def initialize(parent)
          cs = CodeSpace.new
          asm = Assembler.new(cs)
          asm.with_retry do
            asm.ret
          end
          @type = nil
          @type_inference_proc = cs
          @type_cache = nil

          @parent = parent
        end
        attr_accessor :parent

        def inference_type
          cs = @type_inference_proc
          cs.call(cs.base_address)
        end

        def gen_type_inference_proc(code)
        end

        # dummy methods
        def add_modified_var(var, assnode); end
      end

      class HaveChildlenNode<BaseNode
        def initialize(parent)
          super(parent)
          @modified_var = {}
        end

        def traverse_childlen
          raise "You must define traverse_childlen for #{self.inspect}"
        end

        def add_modified_var(lvar, assnode)
          @modified_var[lvar] = [assnode]
          traverse_childlen {|child|
            child.add_modified_var(lvar, assnode)
          }
        end
      end

      # The top of top node
      class TopNode<HaveChildlenNode
        def initialize(parent, name = nil)
          super(parent)
          @name = name
          @body = nil
        end

        attr_accessor :body
        attr_accessor :name

        def traverse_childlen
          yield @body
        end

        def construct_frame_info(locals, argnum)
          finfo = LocalFrameInfoNode.new(self)
          
          # 2 means BP and SP
          lsize = locals.size + 2
          
          # construct frame
          frame_layout = Array.new(lsize)
          i = 0
          fargstart = lsize - argnum
          argnum.times do
            lnode = LocalVarNode.new(finfo, locals[i])
            frame_layout[fargstart + i] = lnode
            i += 1
          end
          
          frame_layout[fargstart - 1] = SystemValueNode.new(finfo, :RET_ADDR)
          frame_layout[fargstart - 2] = SystemValueNode.new(finfo, :OLD_BP)
          i += 2

          j = 0
          while i < lsize do
            lnode = LocalVarNode.new(finfo, locals[i])
            frame_layout[j] = lnode
            i += 1
            j += 1
          end
          finfo.frame_layout = frame_layout
          
          @body = finfo
        end

        def compile(context)
          context = gen_method_prologue(context)
          context = @body.compile(context)
          context
        end
      end

      # Top of method definition
      class MethodTopNode<TopNode
        include MethodTopCodeGen
      end

      class BlockTopNode<TopNode
        include MethodTopCodeGen
      end

      class ClassTopNode<TopNode
        include MethodTopCodeGen
        def initialize(parent, name = nil)
          super(parent, name)
          @nested_class_tab = {}
          @method_tab = {}
        end

        attr :nested_class_tab
        attr :method_tab
      end

      class TopTopNode<ClassTopNode
        include MethodTopCodeGen
      end

      class LocalFrameInfoNode<HaveChildlenNode
        include LocalFrameInfoCodeGen
        
        def initialize(parent)
          super(parent)
          @frame_layout = []
          @body = nil
        end

        attr_accessor :frame_layout
        attr_accessor :body

        def traverse_childlen
          yield @body
          @frame_layout.each do |vinf|
            yield vinf
          end
        end

        def frame_size
          @frame_layout.inject(0) {|sum, slot| sum += slot.size}
        end

        def compile(context)
          if @frame_layout.size != 0 then
            siz = frame_size
            asm = context.assembler
            asm.with_retry do
              asm.sub(SPR, siz)
            end
          end
          context = @body.compile(context)
        end
      end

      class LocalVarNode<BaseNode
        def initialize(parent, name)
          super(parent)
          @name = name
          @assigns = []
        end

        def add_assigns(node)
          @assigns.push node
        end

        def size
          inference_type.asm_type.size
        end

        def compile(context)
          context
        end
      end

      class SystemValueNode<BaseNode
        def initialize(parent, kind)
          @kind = kind
          @offset = offset
        end

        attr :offset

        def size
          Type::MACHINE_WORD.size
        end

        def compile(context)
          context
        end
      end

      # Guard (type information holder and type checking of tree)
      class GuardNode<HaveChildlenNode
      end

      # End of method definition
      class MethodEndNode<BaseNode
        include MethodEndCodeGen

        def initialize(parent)
          super(parent)
          @parent_method = nil
        end

        def compile(context)
          context = gen_method_epilogue(context)
          curas = context.assembler
          curas.with_retry do
            curas.ret
          end
          context
        end
      end

      class BlockEndNode<MethodEndNode
        include MethodEndCodeGen
      end

      class ClassEndNode<MethodEndNode
        include MethodEndCodeGen
      end

      class LocalLabel<HaveChildlenNode
        def initialize(parent, name)
          super(parent)
          @name = name
          @body = nil
        end

        attr :name
        attr_accessor :body
      end

      class BranchCommonNode<HaveChildlenNode
        include IfNodeCodeGen

        def initialize(parent, cond, tpart, epart)
          super(parent)
          @cond = cond
          @tpart = tpart

          @cont_cs = CodeSpace.new
        end

        def traverse_childlen
          yield @cond
          yield @tpart
        end

        def branch(as, address)
          # as.jn(address)
          # as.je(address)
          raise "Don't use this node direct"
        end
          

        def compile(context)
          context = @cond.compile(context)
          contcs = @cont_cs

          curas = context.assembler
          curas.with_retry do
            curas.and(context.ret_reg, OpImmdiate(~4))
            curas.jn(elsecs.var_base_address)
          end

          context = tpart.compile(context)
          tretr = context.ret_reg

          context.add_code_space(contcs)
          cas = context.assembler
          cas.with_retry do
            unify_retreg_cont(tretr, eretr, cas)
          end
          context
        end
      end

      class BranchIfNode<BranchCommonNode
        def branch(as, address)
          as.jn(address)
        end
      end

      class BranchUnlessNode<BranchCommonNode
        def branch(as, address)
          as.je(address)
        end
      end

      # Holder of Nodes Assign. These assignes execute parallel potencially.
      class LetNode<HaveChildlenNode
      end

      # Call methodes
      class CallNode<HaveChildlenNode
        @@current_node = nil
        
        def self.node
          @@current_node
        end

        def initialize(parent)
          super(parent)
          @arguments = []
          @func = nil
          @var_return_address = nil
          @next_node = @@current_node
          @@current_node = self
        end

        attr_accessor :func
        attr_accessor :arguments
        attr          :var_return_address
        attr          :next_node

        def traverse_childlen
          @arguments.each do |arg|
            yield arg
          end
          yield @func
        end

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
        def initialize(parent, val)
          super(parent)
          @value = val
        end
        
        attr :value

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
      class VariableRefCommonNode<BaseNode
      end

      # Local Variable
      class LocalVarRefCommonNode<VariableRefCommonNode
        include LocalVarNodeCodeGen

        def initialize(parent, offset, depth)
          super(parent)
          @offset = offset
          @depth = depth

          tnode = @parent
          while !tnode.is_a?(LocalFrameInfo)
            tnode = tnode.parent
          end
          @frame_info = tnode
        end
      end

      class LocalVarRefNode<LocalVarRefCommonNode
        attr :frame_info

        def compile(context)
          context = gen_pursue_parent_function(context, @depth)
          
        end
      end

      class LocalAssignNode<LocalVarRefCommonNode
        def initialize(parent, offset, depth, val)
          super(parent, offset, depth)
          @val = val
        end

        def compile(context)
          context = gen_pursue_parent_function(context, @depth)
          
        end
      end

      # Instance Variable
      class InstanceVarNode<VariableRefCommonNode
      end

      # Reference Register
      class RefRegister
      end
    end
  end
end

