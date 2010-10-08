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

          # iv for structure of VM
          @parent = parent
          @code_space = nil
          @id = nil
          if @parent then
            @id = @parent.id.dup
            @id[-1] = @id[-1] + 1
          else
            @id = [0]
          end

          # iv for type inference
          @type = nil
          @type_list = TypeUtil::TypeContainer.new
          @element_node_list = []
          @type_inference_proc = cs
          @type_cache = nil

          @ti_observer = {}
        end

        attr_accessor :parent
        attr          :code_space
        attr          :id

        attr_accessor :type
        attr_accessor :element_node_list

        def add_type(key, type)
          @type_list.add_type(key, type)
        end

        def type_list(key)
          @type_list.type_list(key).value
        end

        def set_type_list(key, val)
          @type_list.type_list(key).value = val
        end

        def collect_info(context)
          if is_a?(HaveChildlenMixin) then
            traverse_childlen {|rec|
              context = rec.collect_info(context)
            }
          end

          context
        end

        def ti_add_observer(dst, dkey, skey, upmethod = :ti_update)
          prc = lambda { send(:ti_update, dst, self, dkey, skey) }
          @ti_observer[dst] = prc
        end

        def ti_changed
          @ti_observer.each do |rec, prc|
            prc.call
          end
        end

        def merge_type(dst, src)
          res = dst
          src.each do |sele|
            if ! dst.include? sele then
              res.push sele
            end
          end

          res
        end

        def ti_update(dst, src, dkey, skey)
          dtlist = dst.type_list(dkey)
          stlist = src.type_list(skey)
=begin
          print dkey.map(&:ruby_type), "\n"
          print dtlist.map(&:ruby_type), "\n"
          print stlist.map(&:ruby_type), "\n"
=end
          orgsize = dtlist.size
          dst.set_type_list(dkey, merge_type(dtlist, stlist))

          if orgsize != dtlist.size then
            dst.type = nil
            dst.ti_changed
          end

          dtlist = dst.element_node_list
          stlist = src.element_node_list
          orgsize = dtlist.size
          dst.element_node_list = merge_type(dtlist, stlist)
          if orgsize != dtlist.size then
            dst.ti_changed
          end
        end

        def same_type(dst, src, dkey, skey)
=begin
          print "#{src.class} -> #{dst.class} \n"
          if dst.is_a?(LocalVarNode) then
            print "#{dst.name} \n"
          end
          if dst.is_a?(LiteralNode) then
            print "#{dst.value.inspect} \n"
          end
=end

          if dst.is_a?(BaseNode) then
            src.ti_add_observer(dst, dkey, skey)
          end

          ti_update(dst, src, dkey, skey)
        end

        def add_element_node(key, type)
          slfetnode = @element_node_list
          unless slfetnode.include?(type)
            @element_node_list.push [key, type]
            orgkey = @element_node_list[0][0]
            orgtype = @element_node_list[0][1]
            if orgtype != type then
              same_type(orgtype, type, orgkey, key)
            end
            ti_changed
          end
        end

        def collect_candidate_type(context)
          raise "You must define collect_candidate_type per node"
          context
        end

        def decide_type_core(tlist)
          tlist = tlist.select {|e| e.class != RubyType::DefaultType0 }
          case tlist.size
          when 0
            RubyType::DefaultType0.new
            
          when 1
            if tlist[0].have_element? then
              key = @element_node_list[0][0]
              node = @element_node_list[0][1]
              node.decide_type_once(key)
              tlist[0].element_type = node.type
            end
            tlist[0]
            
          else
            RubyType::DefaultType0.new

          end
        end

        def decide_type_once(key)
          unless @type
            tlist = @type_list.type_list(key).value
            @type = decide_type_core(tlist)
          end
        end

        def decide_type(key)
          decide_type_once(key)

          if is_a?(HaveChildlenMixin) then
            traverse_childlen {|rec|
              rec.decide_type(key)
            }
          end
        end

        def inference_type
          cs = @type_inference_proc
          cs.call(cs.base_address)
        end

        def gen_type_inference_proc(code)
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

        def search_top
          cnode = @parent

          # ClassTopNode include TopTopNode
          while !cnode.is_a?(TopNode)
            cnode = cnode.parent
          end

          cnode
        end

        def search_end
          cnode = @parent

          # ClassTopNode include TopTopNode
          while !cnode.is_a?(MethodEndNode)
            cnode = cnode.body
          end

          cnode
        end

        def search_frame_info
          cnode = @parent

          # ClassTopNode include TopTopNode
          while !cnode.is_a?(LocalFrameInfoNode)
            cnode = cnode.parent
          end

          cnode
        end
      end

      class DummyNode
        def collect_candidate_type(context)
          context
        end

        def compile(context)
          # Not need super because this is dummy
          context
        end
      end

      # The top of top node
      class TopNode<BaseNode
        include HaveChildlenMixin
        include NodeUtil
        def initialize(parent, name = nil)
          super(parent)
          @name = name
          @code_spaces = [] # [[nil, CodeSpace.new]]
          if @parent then
            @classtop = search_class_top
          else
            @classtop = self
          end
          @end_nodes = []
        end

        attr_accessor :name
        attr          :end_nodes

        def modified_instance_var
          search_end.modified_instance_var
        end

        def traverse_childlen
          yield @body
        end

        def find_cs_by_signature(sig)
          @code_spaces.each do |key, val|
            if key == sig then
              return val
            end
          end

          nil
        end

        def add_cs_for_signature(sig)
          cs = find_cs_by_signature(sig)
          if cs then
            return nil

          else
            cs = CodeSpace.new
            @code_spaces.push [sig, cs]
            return cs
          end
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
            lnode = LocalVarNode.new(finfo, locals[i], fargstart + i)
            frame_layout[fargstart + i] = lnode
            i += 1
          end
          
          frame_layout[fargstart - 1] = SystemValueNode.new(finfo, 
                                                            :RET_ADDR, 
                                                            fargstart - 1)
          frame_layout[fargstart - 2] = SystemValueNode.new(finfo, 
                                                            :OLD_BP,
                                                            fargstart - 2)
          frame_layout[fargstart - 3] = SystemValueNode.new(finfo, 
                                                            :OLD_BPSTACK,
                                                            fargstart - 3)

          j = 0
          while i < lsize - 3 do
            lnode = LocalVarNode.new(finfo, locals[i], j)
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

        def collect_info(context)
          context.modified_local_var.push Hash.new
          context.modified_instance_var = {}
          @body.collect_info(context)
        end

        def collect_candidate_type(context, signode, sig)
          if add_cs_for_signature(sig) == nil then
            return context
          end
          context.current_method_signature_node.push signode
          context = @body.collect_candidate_type(context)
          @end_nodes.each do |enode|
            same_type(self, enode, context.to_key, context.to_key)
            same_type(enode, self, context.to_key, context.to_key)
          end
          context.current_method_signature_node.pop
          context
        end

        def disp_signature
          tcontext = CompileContext.new(self)
          @code_spaces.each do |sig, cs|
            tcontext.current_method_signature.push sig
            print sig, " -> "
            tl = @type_list.type_list(tcontext.to_key).value
            print decide_type_core(tl).inspect, "\n"
            tcontext.current_method_signature.pop
          end
        end

        def compile(context)
          @code_spaces.each do |sig, cs|
            context.current_method_signature.push sig
            context.add_code_space(cs)
            context = super(context)
            context.reset_using_reg
            context = gen_method_prologue(context)
            context = @body.compile(context)
            context.current_method_signature.pop
          end

          disp_signature
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
        @@class_top_tab = {}

        def initialize(parent, klassobj, name = nil)
          super(parent, name)
          @nested_class_tab = {}
          @method_tab = {}
          @klass_object = klassobj
          unless @@class_top_tab[klassobj]
            @@class_top_tab[klassobj] = self
          end
        end

        def method_tab(klassobj = nil)
          if klassobj then
            ktop =  @@class_top_tab[klassobj]
            if ktop then
              ktop.method_tab
            else
              {}
            end
          else
            @method_tab
          end
        end

        attr :nested_class_tab
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

        def copy_frame_layout
          @frame_layout.each { |ele| ele.dup }
        end

        attr_accessor :frame_layout
        attr_accessor :argument_num
        attr_accessor :system_num
        attr          :previous_frame

        def traverse_childlen
          @frame_layout.each do |vinf|
            yield vinf
          end
          yield @body
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

        def collect_candidate_type(context)
          traverse_childlen {|rec|
            context = rec.collect_candidate_type(context)
          }
          @body.collect_candidate_type(context)
        end

        def compile(context)
          context = super(context)
          siz = local_area_size
          if  siz != 0 then
            asm = context.assembler
            asm.with_retry do
              asm.sub(SPR, siz)
            end
            cpustack_pushn(siz)
          end
          context = @body.compile(context)
          context
        end
      end

      class LocalVarNode<BaseNode
        def initialize(parent, name, offset)
          super(parent)
          @name = name
          @offset = offset
        end

        attr :name

        def size
          8
        end

        def collect_candidate_type(context)
          flay = @parent.frame_layout
          fragstart = flay.size - @parent.argument_num
          if fragstart <= @offset then
            argoff = @offset - fragstart
            tobj = context.current_method_signature_node.last[argoff]
            if tobj then
              same_type(self, tobj, context.to_key, context.to_key(-2))
              same_type(tobj, self, context.to_key(-2), context.to_key)
            end
          end
          context
        end

        def compile(context)
          context = super(context)
          context
        end
      end

      class SystemValueNode<BaseNode
        def initialize(parent, kind, offset)
          super(parent)
          @kind = kind
          @offset = offset
        end

        attr :offset

        def collect_candidate_type(context)
          context
        end

        def size
          AsmType::MACHINE_WORD.size
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

        def collect_candidate_type(context)
          same_type(self, @parent, context.to_key, context.to_key)
          same_type(@parent, self, context.to_key, context.to_key)
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

        def collect_candidate_type(context)
          context = @value_node.collect_candidate_type(context)
          same_type(self, @value_node, context.to_key, context.to_key)
          same_type(@value_node, self, context.to_key, context.to_key)
          context = @body.collect_candidate_type(context)
          context
        end

        def compile(context)
          context = super(context)
          context = @value_node.compile(context)
          if context.ret_reg != RETR then
            if context.ret_reg.is_a?(OpRegXMM) then
              context = @type.gen_boxing(context)
              if context.ret_reg != RETR then
                curas = context.assembler
                curas.with_retry do
                  curas.mov(RETR, context.ret_reg)
                end
                
                context.set_reg_content(RETR, context.ret_node)
              end
            else
              curas = context.assembler
              curas.with_retry do
                curas.mov(RETR, context.ret_reg)
              end
            end
            context.set_reg_content(TMPR, context.ret_node)
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

        def collect_candidate_type(context)
          @parent.come_from.values.each do |vnode|
            same_type(self, vnode, context.to_key, context.to_key)
            same_type(vnode, self, context.to_key, context.to_key)
          end
          context
        end

        def compile(context)
          context.set_reg_content(TMPR, self)
          context.ret_node = self
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
          @modified_instance_var_list.push modinsvar
          if @modified_instance_var_list.size == @come_from.size then
            context.merge_local_var(@modified_local_var_list)
            context.merge_instance_var(@modified_instance_var_list)
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
            if !context.ret_reg.is_a?(OpRegXMM) then
              if RETR != context.ret_reg then
                asm.with_retry do
                  asm.mov(RETR, context.ret_reg)
                end
                context.set_reg_content(RETR, context.ret_node)
                context.ret_reg = RETR
              end
            end
          end

          context
        end

        def traverse_block_value(comefrom, &block)
          valnode = @come_from[comefrom]
          if valnode then
            yield valnode
          else
            nil
          end
        end

        def collect_candidate_type(context, sender = nil)
          if @come_from.keys[0] == sender then
            context = @body.collect_candidate_type(context)
          end

          context
        end

        def compile(context)
          context = super(context)
          @come_from_val.push context.ret_reg

          # When all node finish to compile, next node compile
          if @come_from_val.size == @come_from.size then
            @body.compile(context)
          else
            context
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

        def traverse_childlen(&block)
          @jmp_to_node.traverse_block_value(self, &block)
          yield @cond
          yield @jmp_to_node
          yield @body
        end

        def branch(as, address)
          # as.jn(address)
          # as.je(address)
          raise "Don't use this node direct"
        end
          
        def collect_candidate_type(context)
          context = @cond.collect_candidate_type(context)
          context = @jmp_to_node.collect_candidate_type(context, self)
          @body.collect_candidate_type(context)
        end

        def compile(context)
          context = super(context)
          context = @jmp_to_node.compile_block_value(context, self)

          jmptocs = @jmp_to_node.code_space
          context = @cond.compile(context)
          curas = context.assembler
          curas.with_retry do
            if context.ret_reg != TMPR then
              curas.mov(TMPR, context.ret_reg)
            end
            
            # In 64bit mode. It will be sign extended to 64 bit
            curas.and(TMPR, OpImmidiate32.new(~4))
          end

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

        def traverse_childlen(&block)
          @jmp_to_node.traverse_block_value(self, &block)
          yield @jmp_to_node
        end

        def collect_candidate_type(context)
          block = lambda {|rec| 
            rec.collect_candidate_type(context)
          }
          tcontext = @jmp_to_node.traverse_block_value(self, &block)
          if tcontext then
            context = tcontext
          end
          @jmp_to_node.collect_candidate_type(context, self)
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
          @type = RubyType::BaseType.from_object(val)
        end
        
        attr :value

        def collect_candidate_type(context)
          @type_list.add_type(context.to_key, @type)
          case @value
          when Array
            key = context.to_key
            @element_node_list = [[key, BaseNode.new(self)]]
            @value.each do |ele|
              etype = RubyType::BaseType.from_object(ele)
              @element_node_list[0][1].add_type(key, etype)
            end
          end
          context
        end

        def compile(context)
          context = super(context)

          decide_type_once(context.to_key)
          case @value
          when Fixnum
            val = @value
            if @type.boxed then
              val = val.boxing
            end
            context.ret_node = self
            context.ret_reg = OpImmidiateMachineWord.new(val)

          when Float
            val = @value
            if @type.boxed then
              val = val.boxing
              context.ret_reg = OpImmidiateMachineWord.new(val)
            else
              offm4 = OpIndirect.new(SPR, -AsmType::DOUBLE.size)
              asm = context.assembler
              asm.with_retry do
                asm.mov64(offm4, val.unboxing)
                asm.movsd(XMM0, offm4)
              end
              context.ret_reg = XMM0
            end
            context.ret_node = self

          else
            if @var_value == nil then
              add = lambda { @value.address }
              @var_value = OpVarImmidiateAddress.new(add)
            end

            context.ret_node = self
            context.ret_reg = @var_value
            context = @type.gen_copy(context)
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

        def collect_candidate_type(context)
          context
        end

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
          @calling_convention = :unkown
          @reciever = nil
          @send_node = nil
        end

        def set_reciever(sendnode)
          @send_node = sendnode
          if sendnode.is_fcall then
            @reciever = @parent.class_top
          else
            @reciever = sendnode.arguments[2]
          end
        end
        
        attr :name
        attr :calling_convention
        attr_accessor :reciever

        def collect_candidate_type(context)
          context
        end

        def set_calling_convention(context)
          if @send_node.is_fcall or @send_node.is_vcall then
            mtop = @reciever.method_tab[@name]
            if mtop then
              @calling_convention = :ytl
            else
              # reciever = Object
              if @reciever.klass_object then
                addr = @reciever.klass_object.method_address_of(@name)
                if addr then
                  if variable_argument?(@eciever.method(@name).parameters) then
                    @calling_convention = :c_vararg
                  else
                    @calling_convention = :c_fixarg
                  end
                else
                  raise "Unkown method - #{@name}"
                  @calling_convention = :c
                end
              else
                raise "foo"
              end
            end
          else
            context = @reciever.compile(context)
            context.ret_node.decide_type_once(context.to_key)
            rtype = context.ret_node.type
            rklass = rtype.ruby_type
            mth = rklass.instance_method(@name)
            if variable_argument?(mth.parameters) then
              @calling_convention = :c_vararg
            else
              @calling_convention = :c_fixarg
            end
          end

          context
        end

        def compile(context)
          context = super(context)
          if @send_node.is_fcall or @send_node.is_vcall then
            asm = context.assembler
            asm.with_retry do
              asm.mov(TMPR3, 4)
            end
            mtop = @reciever.method_tab[@name]
            if mtop then
              sig = @parent.signature(context)
              cs = mtop.find_cs_by_signature(sig)
              context.ret_reg = cs.var_base_address
            else
              if @reciever.klass_object then
                addr = @reciever.klass_object.method_address_of(@name)
                if addr then
                  context.ret_reg = OpMemAddress.new(addr)
                  context.ret_node = self
                else
                  raise "Unkown method - #{@name}"
                  context.ret_reg = OpImmidiateAddress.new(0)
                  context.ret_node = self
                end
              else
                raise "foo"
              end
            end
          else
            context = @reciever.compile(context)
            context.ret_node.decide_type_once(context.to_key)
            rtype = context.ret_node.type
            context = rtype.gen_boxing(context)
            recval = context.ret_reg

            if rtype.is_a?(RubyType::DefaultType0) then
              # Can't type inference. Dynamic method search
              mnval = @name.address
              objclass = OpMemAddress.new(address_of("rb_obj_class"))
              addr = address_of("ytl_method_address_of_raw")
              meaddrof = OpMemAddress.new(addr)

              context.start_using_reg(TMPR2)
              context.start_using_reg(FUNC_ARG[0])
              context.start_using_reg(FUNC_ARG[1])
              
              asm = context.assembler
              asm.with_retry do
                asm.push(recval)
                asm.mov(FUNC_ARG[0], recval)
                asm.call_with_arg(objclass, 1)
                asm.mov(FUNC_ARG[0], RETR)
                asm.mov(FUNC_ARG[1], mnval)
                asm.call_with_arg(meaddrof, 2)
                asm.mov(TMPR2, RETR)
                asm.pop(TMPR3)
              end
              
              context.end_using_reg(FUNC_ARG[1])
              context.end_using_reg(FUNC_ARG[0])
              
              context.ret_node = self
              context.set_reg_content(RETR, self)
              context.set_reg_content(TMPR2, self)
              context.set_reg_content(TMPR3, @reciever)
              context.ret_reg = TMPR2
            else
              asm = context.assembler
              asm.with_retry do
                asm.mov(TMPR3, recval)
              end

              addr = rtype.ruby_type.method_address_of(@name)
              if addr then
                context.ret_reg = OpMemAddress.new(addr)
                context.ret_node = self
              else
                raise "Unkown method - #{@name}"
                context.ret_reg = OpImmidiateAddress.new(0)
                context.ret_node = self
              end
            end
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
        include NodeUtil

        def initialize(parent, offset, depth)
          super(parent)
          @offset = offset
          @depth = depth

          tnode = search_frame_info
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

        def collect_candidate_type(context)
          @var_type_info.each do |src|
            same_type(self, src, context.to_key, context.to_key)
          end
          context
        end

        def compile(context)
          context = super(context)
          context = gen_pursue_parent_function(context, @depth)
          asm = context.assembler
          base = context.ret_reg
          offarg = @current_frame_info.offset_arg(@offset, base)
          context.ret_node = self
          context.ret_reg = offarg
          context
        end
      end

      class SelfRefNode<LocalVarRefNode
        def initialize(parent)
          super(parent, 0, 2)
          @classtop = search_class_top
        end

        def compile_main(context)
          context = gen_pursue_parent_function(context, @depth)
          base = context.ret_reg
          offarg = @current_frame_info.offset_arg(@offset, base)
          context.ret_node = self
          context.ret_reg = offarg
        end

        def collect_candidate_type(context)
          @type = RubyType::BaseType.from_ruby_class(@classtop.klass_object)
          @type_list.add_type(context.to_key, @type)
          context
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
          
        def collect_candidate_type(context)
          context = @val.collect_candidate_type(context)
          same_type(self, @val, context.to_key, context.to_key)
          @body.collect_candidate_type(context)
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

          else
            asm.with_retry do
              asm.mov(TMPR, valr)
              asm.mov(offarg, TMPR)
            end
          end
          
          context.ret_reg = nil
          context = @body.compile(context)
          context
        end
      end

      # Instance Variable
      class InstanceVarRefCommonNode<VariableRefCommonNode
        include NodeUtil

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

        def collect_candidate_type(context)
          @var_type_info.each do |src|
            same_type(self, src, context.to_key, context.to_key)
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

      class InstanceVarAssignNode<InstanceVarRefCommonNode
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
          context.modified_instance_var[@name] = [self]
          @body.collect_info(context)
        end

        def collect_candidate_type(context)
          context = @val.collect_candidate_type(context)
          same_type(self, @val, context.to_key, context.to_key)
          @body.collect_candidate_type(context)
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
