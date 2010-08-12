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
BranchIfNode
  epart------------------+
  tpart----------------+ |
  cond                 | |
   |                   | |
SendNode               | |
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
SendNode
   func -> *
   arg[0] --------------+
   arg[1]               |
    |                   |
SendNode                |
   func -> fact         |
   arg[0]               |
    |                   |
SendNode                |
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
        include AbsArch
        def initialize(parent)
          cs = CodeSpace.new
          asm = Assembler.new(cs)
          asm.with_retry do
            asm.mov(TMPR, 4)
            asm.ret
          end
          @type = RubyType::DefaultType.new
          @type_inference_proc = cs
          @type_cache = nil

          @parent = parent
          @code_space = nil
          @id = nil
          if @parent then
            @id = @parent.id.dup
            @id[-1] = @id[-1] + 1
          else
            @id = [0]
          end
        end

        attr_accessor :parent
        attr          :code_space
        attr_accessor :type
        attr          :id

        def inference_type
          cs = @type_inference_proc
          cs.call(cs.base_address)
        end

        def gen_type_inference_proc(code)
        end

        def collect_info(context)
          if is_a?(HaveChildlenMixin) then
            traverse_childlen {|rec|
              context = rec.collect_info(context)
            }
          end

          context
        end

        def compile(context)
          @code_space = context.code_space
          context
        end
      end
      
      module HaveChildlenMixin
        def initialize(*args)
          super
          @body = DummyNode.new
        end

        attr_accessor :body

        def traverse_childlen
          raise "You must define traverse_childlen #{self.class}"
        end
      end

      module NodeUtil
        def search_class_top
          cnode = @parent

          # ClassTopNode include TopTopNode
          while !cnode.is_a?(ClassTopNode)
            cnode = cnode.parent
          end

          cnode
        end
      end

      class DummyNode
        def compile(context)
          # Not need super because this is dummy
          context
        end
      end

      # The top of top node
      class TopNode<BaseNode
        include HaveChildlenMixin
        def initialize(parent, name = nil)
          super(parent)
          @name = name
          @code_space = CodeSpace.new
        end

        attr_accessor :name

        def traverse_childlen
          yield @body
        end

        def collect_info(context)
          context.modified_local_var.push Hash.new
          context.modified_instance_var = {}
          @body.collect_info(context)
        end

        def construct_frame_info(locals, argnum)
          finfo = LocalFrameInfoNode.new(self)
          
          # 3 means BP, BP and SP
          lsize = locals.size + 3
          
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
          frame_layout[fargstart - 3] = SystemValueNode.new(finfo, :OLD_BPSTACK)

          j = 0
          while i < lsize - 3 do
            lnode = LocalVarNode.new(finfo, locals[i])
            frame_layout[j] = lnode
            i += 1
            j += 1
          end
          finfo.frame_layout = frame_layout
          finfo.argument_num = argnum
          finfo.system_num = 3         # BP ON Stack, BP, RET
          
          @body = finfo
          finfo
        end

        def compile(context)
          context.add_code_space(@code_space)
          context = super(context)
          context.reset_using_reg
          context = gen_method_prologue(context)
          context = @body.compile(context)
          context
        end
      end

      # Top of method definition
      class MethodTopNode<TopNode
        include MethodTopCodeGen
        def construct_frame_info(locals, argnum)
          locals.unshift :_self
          locals.unshift :_block
          locals.unshift :_prev_env
          argnum += 3
          super(locals, argnum)
        end
      end

      class BlockTopNode<MethodTopNode
        include MethodTopCodeGen
      end

      class ClassTopNode<TopNode
        include MethodTopCodeGen
        def initialize(parent, klassobj, name = nil)
          super(parent, name)
          @nested_class_tab = {}
          @method_tab = {}
          @klass_object = klassobj
        end

        attr :nested_class_tab
        attr :method_tab
        attr :klass_object

        def construct_frame_info(locals, argnum)
          locals.unshift :_self
          locals.unshift :_block
          locals.unshift :_prev_env
          argnum += 3
          super(locals, argnum)
        end
      end

      class TopTopNode<ClassTopNode
        include MethodTopCodeGen

        def initialize(parent, klassobj, name = :top)
          super
          
          @code_space_tab = []
          @id.push 0
        end

        def add_code_space(oldcs, newcs)
          if !@code_space_tab.include?(newcs) then
            @code_space_tab.push newcs
          end
        end

        attr :code_space_tab
      end

      class LocalFrameInfoNode<BaseNode
        include HaveChildlenMixin
        
        def initialize(parent)
          super(parent)
          @frame_layout = []
          @argument_num = nil
          @system_num = nil
          @previous_frame = search_previous_frame(parent)
          @offset_cache = {}
        end

        def search_previous_frame(mtop)
          cnode = mtop.parent
          while !cnode.is_a?(TopNode)
            if cnode then
              cnode = cnode.parent
            else
              return nil
            end
          end

          return cnode.body
        end

        attr_accessor :frame_layout
        attr_accessor :argument_num
        attr_accessor :system_num
        attr          :previous_frame

        def traverse_childlen
          yield @body
          @frame_layout.each do |vinf|
            yield vinf
          end
        end

        def frame_size
          @frame_layout.inject(0) {|sum, slot| sum += slot.size}
        end

        def local_area_size
          localnum = @frame_layout.size - @argument_num - @system_num
          @frame_layout[0, localnum].inject(0) {|sum, slot| sum += slot.size}
        end

        def real_offset(off)
          if off >=  @argument_num then
            off = off - @argument_num
          else
            off = off + (@frame_layout.size - @argument_num)
          end

          off
        end

        def offset_by_byte(off)
          off = real_offset(off)

          obyte = 0
          off.times do |i|
            obyte += @frame_layout[i].size
          end
          
          obyte - local_area_size
        end

        def offset_arg(n, basereg)
          rc = @offset_cache[n]
          unless rc
            off = offset_by_byte(n)
            rc = @offset_cache[n] = OpIndirect.new(basereg, off)
          end

          rc
        end

        def compile(context)
          context = super(context)
          siz = local_area_size
          if  siz != 0 then
            asm = context.assembler
            asm.with_retry do
              asm.sub(SPR, siz)
            end
          end
          context = @body.compile(context)
          context
        end
      end

      class LocalVarNode<BaseNode
        def initialize(parent, name)
          super(parent)
          @name = name
        end

        def size
          8
        end

        def compile(context)
          context = super(context)
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
          context = super(context)
          context
        end
      end

      # Guard (type information holder and type checking of tree)
      class GuardNode<BaseNode
        include HaveChildlenMixin
      end

      # End of method definition
      class MethodEndNode<BaseNode
        include MethodEndCodeGen

        def initialize(parent)
          super(parent)
          @modified_instance_var = nil
        end

        attr :modified_instance_var

        def collect_info(context)
          context.modified_local_var.pop
          @modified_instance_var = context.modified_instance_var
          context
        end

        def compile(context)
          context = super(context)
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

      # Set result of method/block
      class SetResultNode<BaseNode
        include HaveChildlenMixin

        def initialize(parent, valnode)
          super(parent)
          @value_node = valnode
        end

        def traverse_childlen
          yield @value_node
          yield @body
        end

        def compile(context)
          context = super(context)
          context = @value_node.compile(context)
          curas = context.assembler
          if context.ret_reg != RETR then
            curas.with_retry do
              curas.mov(RETR, context.ret_reg)
            end
          end

          context.ret_reg = RETR
          context = @body.compile(context)

          context
        end
      end

      class PhiNode<BaseNode
        def initialize(parent)
          super(parent)
        end

        def compile(context)
          context.ret_reg = RETR
          context
        end
      end

      class LocalLabel<BaseNode
        include HaveChildlenMixin
        def initialize(parent, name)
          super(parent)
          @name = name
          @come_from = {}
          @come_from_val = []
          @code_space = CodeSpace.new
          @value_node = PhiNode.new(self)
          @modified_local_var_list = []
          @modified_instance_var_list = []
        end

        attr :name
        attr :come_from
        attr :value_node

        def traverse_childlen
          yield @body
          yield @value_node
        end

        def collect_info(context)
          modlocvar = context.modified_local_var.map {|ele| ele.dup}
          @modified_local_var_list.push modlocvar
          modinsvar = context.modified_instance_var.dup
          @modified_instance_var_list.push modlocvar
          if @modified_instance_var_list.size == @come_from.size
            context.merge_local_var(@modified_loca_var_list)
            context.merge_instance_var(@modified_loca_var_list)
            @body.collect_info(context)
          else
            context
          end
        end

        def compile_block_value(context, comefrom)
          valnode = @come_from[comefrom]
          if valnode then
            context = valnode.compile(context)
            asm = context.assembler
            asm.with_retry do
              asm.mov(RETR, context.ret_reg)
            end
          end

          context
        end

        def compile(context)
          context = super(context)
          @come_from_val.push context.ret_reg

          # When all node finish to compile, next node compile
          if @come_from_val.size == @come_from.size then
            context = @body.compile(context)
          end

          context
        end
      end

      class BranchCommonNode<BaseNode
        include HaveChildlenMixin
        include IfNodeCodeGen

        def initialize(parent, cond, jmpto)
          super(parent)
          @cond = cond
          @jmp_to_node = jmpto
        end

        def traverse_childlen
          yield @cond
          yield @jmp_to_node
          yield @body
        end

        def branch(as, address)
          # as.jn(address)
          # as.je(address)
          raise "Don't use this node direct"
        end
          

        def compile(context)
          context = super(context)
          jmptocs = @jmp_to_node.code_space
          context = @jmp_to_node.compile_block_value(context, self)

          context.start_using_reg(TMPR)
          context = @cond.compile(context)
          curas = context.assembler
          curas.with_retry do
            if context.ret_reg != TMPR then
              curas.mov(TMPR, context.ret_reg)
            end
            
            # In 64bit mode. It will be sign extended to 64 bit
            curas.and(TMPR, OpImmidiate32.new(~4))
          end

          # pop don't move condition flags
          context.end_using_reg(TMPR)

          curas.with_retry do
            branch(curas, jmptocs.var_base_address)
          end

          context = @body.compile(context)
          context.add_code_space(jmptocs)
          context = @jmp_to_node.compile(context)

          context
        end
      end

      class BranchIfNode<BranchCommonNode
        def branch(as, address)
          as.jnz(address)
        end
      end

      class BranchUnlessNode<BranchCommonNode
        def branch(as, address)
          as.jz(address)
        end
      end

      class JumpNode<BaseNode
        include HaveChildlenMixin

        def initialize(parent, jmpto)
          super(parent)
          @jmp_to_node = jmpto
        end

        def traverse_childlen
          yield @jmp_to_node
        end

        def compile(context)
          context = super(context)

          context = @jmp_to_node.compile_block_value(context, self)

          jmptocs = @jmp_to_node.code_space
          curas = context.assembler
          curas.with_retry do
            curas.jmp(jmptocs.var_base_address)
          end

          context.add_code_space(jmptocs)
          context = @jmp_to_node.compile(context)
          context
        end
      end

      # Holder of Nodes Assign. These assignes execute parallel potencially.
      class LetNode<BaseNode
        include HaveChildlenMixin
      end

      # Literal
      class LiteralNode<BaseNode
        def initialize(parent, val)
          super(parent)
          @value = val
          @type = RubyType::BaseType.from_object(@value)
        end
        
        attr :value

        def compile(context)
          context = super(context)

          case @value
          when Fixnum
            val = @value
            if @type.boxed then
              val = val.boxing
            end
            context.ret_reg = OpImmidiateMachineWord.new(val)

          else
            context.ret_reg = OpImmidiateAddress.new(@value.address)
          end

          context
        end
      end

      class SpecialObjectNode<BaseNode
        def initialize(parent, kind)
          super(parent)
          @kind = kind
        end
        
        attr :kind

        def compile(context)
#          raise "Can't compile"
          context = super(context)
          context
        end
      end

      # Method name
      class MethodSelectNode<BaseNode
        def initialize(parent, val)
          super(parent)
          @name = val
          @written_in = :unkown
          @reciever = nil
          @send_node = nil
        end

        def set_reciever(sendnode)
          @send_node = sendnode
          if sendnode.is_fcall then
            @reciever = @parent.class_top
          else
            @reciever = sendnode.arguments[0]
          end
        end
        
        attr :name
        attr :written_in
        attr_accessor :reciever

        def compile(context)
          context = super(context)
          if @send_node.is_fcall or @send_node.is_vcall then
            mtop = @reciever.method_tab[@name]
            if mtop then
              context.ret_reg = mtop.code_space.var_base_address
              @written_in = :ytl
            else
              # reciever = Object
              if @reciever.klass_object then
                addr = @reciever.klass_object.method_address_of(@name)
                if addr then
                  context.ret_reg = OpMemAddress.new(addr)
                  if variable_argument?(@eciever.method(@name).parameters) then
                    @written_in = :c_vararg
                  else
                    @written_in = :c_fixarg
                  end
                else
                  raise "Unkown method - #{@name}"
                  context.ret_reg = OpImmidiateAddress.new(0)
                  @written_in = :c
                end
              else
                raise "foo"
              end
            end
          else
            context = @reciever.compile(context)
            recval = context.ret_reg
            mnval = @name.address
                
            objclass = OpMemAddress.new(address_of("rb_obj_class"))

            addr = address_of("ytl_method_address_of_raw")
            meaddrof = OpMemAddress.new(addr)
            context.start_using_reg(TMPR2)
            asm = context.assembler
            asm.with_retry do
              asm.mov(FUNC_ARG[0], recval)
              asm.call_with_arg(objclass, 1)
              asm.mov(FUNC_ARG[0], RETR)
              asm.mov(FUNC_ARG[1], mnval)
              asm.call_with_arg(meaddrof, 2)
              asm.mov(TMPR2, RETR)
            end

            context.ret_reg = TMPR2
            @written_in = :c_fixarg
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

          tnode = parent
          while tnode and !tnode.is_a?(LocalFrameInfoNode)
            tnode = tnode.parent
          end
          @frame_info = tnode
          
          depth.times do |i|
            tnode = tnode.previous_frame
          end
          @current_frame_info = tnode
        end

        attr :frame_info
        attr :current_frame_info
      end

      class LocalVarRefNode<LocalVarRefCommonNode
        def initialize(parent, offset, depth)
          super
          @var_type_info = nil
        end

        def collect_info(context)
          vti = context.modified_local_var[@depth][@offset]
          if vti then
            @var_type_info = vti.dup
          else
            roff = @current_frame_info.real_offset(@offset)
            @var_type_info = [@current_frame_info.frame_layout[roff]]
          end

          context
        end

        def compile(context)
          context = super(context)
          context = gen_pursue_parent_function(context, @depth)
          asm = context.assembler
          base = context.ret_reg
          offarg = @current_frame_info.offset_arg(@offset, base)
          context.ret_reg = offarg
          context
        end
      end

      class SelfRefNode<LocalVarRefNode
        include NodeUtil

        def initialize(parent)
          super(parent, 0, 0)
          @classtop = search_class_top
        end

        def compile_main(context)
          context = gen_pursue_parent_function(context, @depth)
          base = context.ret_reg
          offarg = @current_frame_info.offset_arg(@offset, base)
          context.ret_reg = offarg
        end

        def compile(context)
          context = super(context)
          comile_main(context)
        end
      end

      class LocalAssignNode<LocalVarRefCommonNode
        include HaveChildlenMixin
        def initialize(parent, offset, depth, val)
          super(parent, offset, depth)
          val.parent = self
          @val = val
        end

        def traverse_childlen
          yield @val
          yield @body
        end

        def collect_info(context)
          context = @val.collect_info(context)
          context.modified_local_var[@depth][@offset] = [self]
          @body.collect_info(context)
        end
          
        def compile(context)
          context = super(context)
          context = @val.compile(context)
          valr = context.ret_reg
          context = gen_pursue_parent_function(context, @depth)
          base = context.ret_reg
          offarg = @current_frame_info.offset_arg(@offset, base)

          asm = context.assembler
          if valr.is_a?(OpRegistor) or valr.is_a?(OpImmidiate) then
            asm.with_retry do
              asm.mov(offarg, valr)
            end
            context.end_using_reg(valr)

          else
            context.start_using_reg(TMPR)
            asm.with_retry do
              asm.mov(TMPR, valr)
              asm.mov(offarg, TMPR)
            end
            context.end_using_reg(TMPR)
            context.end_using_reg(valr)
          end
          
          context.ret_reg = valr
          context = @body.compile(context)
          context
        end
      end

      # Instance Variable
      class InstanceVarRefCommonNode<VariableRefCommonNode
        def initialize(parent, name)
          super(parent)
          @name = name
          @class_top = search_class_top
        end
      end

      class InstanceVarRefNode<InstanceVarRefCommonNode
        def initialize(parent, name)
          super
          @var_type_info = nil
        end

        def collect_info(context)
          vti = context.modified_instance_var[@name]
          if vti then
            @var_type_info = vti.dup
          else
            @var_type_info = nil
          end

          context
        end

        def compile_main(context)
          context
        end

        def compile(context)
          context = super(context)
          compile_main(context)
        end
      end

      class InstanceAssignNode<InstanceVarRefCommonNode
        include HaveChildlenMixin
        def initialize(parent, name, val)
          super(parent, name)
          val.parent = self
          @val = val
        end

        def traverse_childlen
          yield @val
          yield @body
        end

        def collect_info(context)
          context = @val.collect_info(context)
          context.modified_local_var[@name] = [self]
          @body.collect_info(context)
        end

        def compile_main(context)
          context
        end

        def compile(context)
          context = super(context)
          compile_main(context)
        end
      end

      # Reference Register
      class RefRegister
      end
    end
  end
end

