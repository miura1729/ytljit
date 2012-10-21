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
      module TypeListWithSignature
        def type_list_initvar
          TypeUtil::TypeContainer.new
        end
        
        def type_list(sig)
          @type_list.type_list(sig).value
        end

        def set_type_list(sig, val, pos = 1)
          @type_list.type_list(sig).value[pos] = val
        end

        def add_type(sig, type, pos = 0)
          @type_list.add_type(sig, type, pos)
          if type.have_element? then
            if @my_element_node == nil then
              @my_element_node = BaseNode.new(self)
            end
            if @element_node_list == [] then
              @element_node_list = [[type, sig, @my_element_node, nil]]
            end
          end
        end
      end

      module TypeListWithoutSignature
        def type_list_initvar
          [[], []]
        end
        
        def type_list(sig)
          @type_list
        end

        def set_type_list(sig, val, pos = 1)
          @type_list[pos] = val
        end

        def add_type(sig, type, pos = 0)
          tvsv = @type_list[pos]
          if !tvsv.include? type then
            tvsv.push type
          end
          if type.have_element? then
            if @my_element_node == nil then
              @my_element_node = BaseNode.new(self)
            end
            if @element_node_list == [] then
              @element_node_list = [[type, sig, @my_element_node, nil]]
            end
          end
        end
      end
      
      class BaseNode
        include Inspect
        include AbsArch
        include TypeListWithSignature

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
          @id = [1]
          if @parent then
            @id = @parent.id.dup
            @id[-1] = @id[-1] + 1
          else
            @id = [1]
          end

          # iv for type inference
          @type = nil
          @type_list = type_list_initvar
          @element_node_list = []
          @my_element_node = nil
          @type_inference_proc = cs
          @decided_signature = nil
          @is_escape = nil

          @ti_observer = {}
          @ti_observee = []

          @debug_info = nil
        end

        attr_accessor :parent
        attr          :code_space
        attr          :id

        attr_accessor :type
        attr_accessor :element_node_list
        attr_accessor :is_escape

        attr          :ti_observer
        attr          :ti_observee

        attr_accessor :debug_info

        def collect_info(context)
          if is_a?(HaveChildlenMixin) then
            traverse_childlen {|rec|
              context = rec.collect_info(context)
            }
          end

          context
        end

        def ti_add_observer(dst, dsig, ssig, context)
          if @ti_observer[dst] == nil then
            @ti_observer[dst] = []
            dst.ti_observee.push self
          end
          
          if @ti_observer[dst].all? {|edsig, essig, eprc| 
              (edsig != dsig) or (essig != ssig)
            } then
            prc = lambda { send(:ti_update, dst, self, dsig, ssig, context) }
            @ti_observer[dst].push [dsig, ssig, prc]
          end
        end

        def ti_changed
          @ti_observer.keys.each do |rec|
            lst = @ti_observer[rec]
            lst.each do |dsig, ssig, prc|
              prc.call
            end
          end
        end

        def ti_reset(visitnode = {})
          if visitnode[self] then
            return
          end

          visitnode[self] = true
          @ti_observer.each do |rec, lst|
            lst.each do |dsig, ssig, prc|
              rec.type_list(dsig)[1] = []

              rec.ti_reset(visitnode)
            end
          end
        end

        def ti_del_link(visitnode = {})
          if visitnode[self] then
            return
          end

          visitnode[self] = true
          @ti_observer.each do |rec, lst|
            delent = []
            lst.each do |ent|
              delent.push ent
                
              rec.ti_del_link(visitnode)
            end

            delent.each do |ent|
              lst.delete(ent)
            end
          end
        end

        def merge_element_node(dst, src, context)
          res = dst
          src.each do |sele|
            exist_same_type = false
#=begin
            res.each do |rele|
              if rele[3] == sele[3] and
                  rele[1] == sele[1] then
                if rele[2] != sele[2] then
                  # Add entry for old element type version of self
                  rtype = rele[2].decide_type_once(rele[1])
                  if rtype == nil or 
                      rtype.ruby_type == NilClass then
                    nele = [rele[0], sele[1], sele[2], sele[3]]
                    if !res.include?(nele) then
                      res.push nele
                    end
                  end
                end
                if rele[0] == sele[0] then
                  exist_same_type = true
                end
              end
            end
#=end
            
            if !exist_same_type and !res.include?(sele) then
              res.push sele
            end
          end
          
          res
        end

        def merge_type(dst, src)
          res = dst
          src.each do |sele|
            org = nil
            res.delete_if {|e| 
              if e.ruby_type == sele.ruby_type and
                  e.boxed == sele.boxed then
                org = e
              else
                nil
              end
            }

            if org and org.have_element? and org.element_type then
              res.push org
            else
              res.push sele
            end
          end
          
          res
        end

        def ti_update(dst, src, dsig, ssig, context)
          dtlistorg = dst.type_list(dsig)
          dtlist = dtlistorg.flatten
          stlist = src.type_list(ssig).flatten
=begin
          print "UPDATE TYPE\n"
          print "#{src.class} #{ssig.inspect} -> #{dst.class} #{dsig.inspect}\n"
          print dtlist.map(&:ruby_type), "\n"
          print stlist.map(&:ruby_type), "\n"
=end
          orgsize = dtlist.size
#          pp "#{dst.class} #{src.class} #{dtlist} #{stlist}"
          newdt = merge_type(dtlistorg[1], stlist)
          dst.set_type_list(dsig, newdt)
          dtsize = dtlistorg[0].size + newdt.size

          if orgsize != dtsize then
            dst.type = nil
            dst.ti_changed
            context.convergent = false
          end

          dtlist = dst.element_node_list
          stlist = src.element_node_list

          orgsize = dtlist.size
          dst.element_node_list = merge_element_node(dtlist, stlist, context)
          if orgsize != dtlist.size then
            dst.ti_changed
            context.convergent = false
          end
          
          dst.set_escape_node(src.is_escape)
        end

        def same_type(dst, src, dsig, ssig, context)
=begin
          print "#{src.class} -> #{dst.class} \n"
          if dst.is_a?(LocalVarNode) then
            print "#{dst.name} \n"
          end
          if dst.is_a?(LiteralNode) then
            print "#{dst.value.inspect} \n"
          end
          if dst.is_a?(SendNode) then
            print "#{dst.func.name} \n"
          end
=end

          if dst.is_a?(BaseNode) then
            src.ti_add_observer(dst, dsig, ssig, context)
          end

          ti_update(dst, src, dsig, ssig, context)
        end

        def add_element_node_backward(args)
          add_element_node(*args)
          visitnode = {}
          visitnode[self] = true
          @ti_observee.each do |rec|
            rec.add_element_node(*args, true)
#            rec.add_element_node_backward_aux(args, visitnode)
          end
        end

        def add_element_node_backward_aux(args, visitnode)
          if visitnode[self] then
            return
          end

          add_element_node(*args, true)
          visitnode[self] = true
          @ti_observee.each do |rec|
            rec.add_element_node_backward_aux(args, visitnode)
          end
        end

        ESCAPE_LEVEL = {
          nil => -1, 
          :not_export => 5, 
          :local_export => 6,
          :global_export => 10
        }
          
        def set_escape_node(value)
          if ESCAPE_LEVEL[@is_escape] < ESCAPE_LEVEL[value] then
            @is_escape = value
          end
        end

        def set_escape_node_backward(value, visitnode = {})
          if visitnode[self] then
            return
          end

          set_escape_node(value)

          visitnode[self] = true
          @ti_observee.each do |rec|
            rec.set_escape_node_backward(value, visitnode)
          end
        end

        def add_element_node(curslf, encsig, enode, index, context, 
                             backp = false)
          newele = [curslf, encsig, enode, index]

          # search entry whose index( [3]) is nil
          nlentry = nil
          @element_node_list.each do |e| 
            if e[1] == encsig and
                e[0] == curslf and
                e[3] == nil then
              nlentry = e
              break
            end
          end

          # entry nil index of new self to non-empty table 
          if nlentry == nil then
            nlnode = BaseNode.new(nil)
            nlentry = [curslf, encsig, nlnode, nil]
            @element_node_list.push nlentry
          end

          if !@element_node_list.include?(newele) then
            @element_node_list.push newele
            nelesig = nlentry[1]
            nelenode = nlentry[2]
            if nelenode != enode then
              same_type(nelenode, enode, nelesig, encsig, context)
            end
            if index != nil then
              @element_node_list.each do |tmpslf, tmpsig, tmpnode, tmpindex|
                if tmpslf == curslf and
                    tmpindex == index and
                    tmpnode != enode then
                  same_type(tmpnode, enode, tmpsig, encsig, context)
                end
              end
            end
            
            if !backp then
              ti_changed
            end
            #            context.convergent = false
          end
        end

        def collect_candidate_type(context)
          raise "You must define collect_candidate_type per node"
          context
        end

        def decide_type_core(tlist, cursig, local_cache = {})
          tlist = tlist.select {|e| e.class != RubyType::DefaultType0 }

          # This is for sitration of same class and differenc element type.
          # Last element must be local type not propageted type
          if tlist.size > 1 and tlist.all? {|e| 
              e.ruby_type == tlist[0].ruby_type and
              e.boxed == tlist[0].boxed
            } then
            return tlist.last
          end

          case tlist.size
          when 0
            RubyType::DefaultType0.new # .to_unbox

          when 1
            tlist[0]

          when 2
            if tlist[0].ruby_type == tlist[1].ruby_type then
              if tlist[0].include_nil? then
                tlist[0]
              else
                tlist[1]
              end

            elsif tlist[0].ruby_type == NilClass then
              # nil-able type
              if tlist[1].include_nil? then
                tlist[1]
              else
                tlist[1].to_box
              end

            elsif tlist[1].ruby_type == NilClass then
              # nil-able type
              if tlist[0].include_nil? then
                tlist[0]
              else
                tlist[0].to_box
              end

            elsif tlist[0].ruby_type == Float and
                tlist[1].ruby_type == Fixnum then
              tlist[0]

            elsif tlist[0].ruby_type == Fixnum and
                tlist[1].ruby_type == Float then
              tlist[1]

            elsif tlist[0].ruby_type == TrueClass and
                tlist[1].ruby_type == FalseClass then
              tlist[0]

            elsif tlist[0].ruby_type == FalseClass and
                tlist[1].ruby_type == TrueClass then
              tlist[1]

            else 
              RubyType::DefaultType0.new
            end

          when 3
            tmptlist = tlist.dup
            tmptlist.delete_if {|ele| ele.ruby_type == NilClass}
            if tmptlist.size < 3 then
              # retry nil deleted entry
              res = decide_type_core(tmptlist, cursig, local_cache)
              if res.include_nil? then
                res
              else
                res.to_box
              end

            elsif tmptlist[0].ruby_type == tmptlist[1].ruby_type and
                  tmptlist[0].ruby_type == tmptlist[2].ruby_type  then
#              if tlist[0].boxed or tlist[0].include_nil? then
#                tlist[0]
#              else
#                decide_type_core(tmptlist[1..2], cursig, local_cache)
#              end
              tmptlist[1]

            elsif tmptlist[2].ruby_type == tmptlist[0].ruby_type then
              tmptlist[0] = tmptlist[0].to_box
              decide_type_core(tmptlist[0..1], cursig, local_cache)

            elsif tmptlist[2].ruby_type == tmptlist[1].ruby_type then
              tmptlist[1] = tmptlist[1].to_box
              decide_type_core(tmptlist[0..1], cursig, local_cache)

            elsif  tmptlist[1].ruby_type == tmptlist[0].ruby_type then
              tmptlist[1] = tmptlist[2]
              tmptlist[0] = tmptlist[0].to_box
              decide_type_core(tmptlist[0..1], cursig, local_cache)

            else
              RubyType::DefaultType0.new
            end

          else
            RubyType::DefaultType0.new
          end
        end

        def decide_type_once(cursig, local_cache = {})
          if local_cache[self] then
            return local_cache[self] 
          end

=begin
          if @decided_signature and @decided_signature != sig then
            p cursig
            p @decided_signature
            p debug_info
            p self.class
            p caller[0]
            @decided_signature = cursig
          end
=end

          if  # @decided_signature != cursig or
              @type.equal?(nil) or 
              @type.is_a?(RubyType::DefaultType0) then
            tlist = type_list(cursig).flatten.reverse.uniq
            @decided_signature = cursig
            @type = decide_type_core(tlist, cursig, local_cache)
          end

          if @type.have_element? and 
              (@type.element_type == nil or
               @type.element_type == {}) then
            local_cache[self] = @type
            etype2 = {}
            etype = nil
            @element_node_list.each do |ele|
              node = ele[2]
              sig = ele[1]
              slf = ele[0]

              if @type == slf then
                # node.type = nil
                tt = node.decide_type_once(sig, local_cache)
                etype2[ele[3]] ||= []
                curidx = etype2[ele[3]]
                if tt.ruby_type != Object and !curidx.include?(tt) then
                  curidx.push tt
                  etype = etype2
                end
              end
            end
            @type.element_type = etype
          end

          @type
        end

        def decide_type(sig)
          decide_type_once(sig)

          if is_a?(HaveChildlenMixin) then
            traverse_childlen {|rec|
              rec.decide_type(sig)
            }
          end
        end

        def search_valid_signature
          node = @type_list.search_valid_node
          if node then
            node.key
          else
            nil
          end
        end

        def inference_type
          cs = @type_inference_proc
          cs.call(cs.var_base_address)
        end

        def gen_type_inference_proc(code)
        end

        def compile(context)
          @code_space = context.code_space
          context
        end

        def get_constant_value
          nil
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
          cnode = self

          # MethodEndNode include ClassEndNode
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

        def search_frame_info_without_inline
          fnode = search_frame_info
          while fnode.parent.is_a?(BlockTopInlineNode)
            fnode = fnode.previous_frame
          end
          fnode
        end
      end

      module SendUtil
        include AbsArch

        def gen_eval_self(context)
          # eval 1st arg(self)
          slfnode = @arguments[2]
          context = slfnode.compile(context)

          rnode = context.ret_node
#          rnode.type = nil
          rtype = rnode.decide_type_once(context.to_signature)
          if !rtype.boxed then
            context = rtype.gen_unboxing(context)
          end
          context
        end

        def signature(context, args = @arguments)
          res = []
          cursig = context.to_signature
          if args[1].is_a?(BlockTopNode) then 
            res.push cursig[1]
          else
            res.push args[0].decide_type_once(cursig)
          end
          if @func.is_a?(YieldNode) then
            res.push cursig[0]
          else
            res.push args[1].decide_type_once(cursig)
          end

          mt, slf = get_send_method_node(cursig)
          res.push slf

          lstarg = -1
          if is_args_splat then
            lstarg = -2
          end

          args[3..lstarg].each do |ele|
            if ele.type_list(cursig) == [[], []] and ele.type then
              res.push ele.type
            else
              ele.type = nil
              res.push ele.decide_type_once(cursig)
            end
          end

          if is_args_splat then
            ele = args[-1]
            if ele.type_list(cursig) != [[], []] or !ele.type then
              ele.type = nil
              ele.decide_type_once(cursig)
            end
            i = 0
            tt = nil
            if ele.type.element_type then
              while tt = ele.type.element_type[[i]]
                res.push tt[0]
                i += 1
              end
            end
            if i == 0 then
              # Have no type info each element. So use total type info
              # I don't know number of element :(
              num = mt.body.argc - @arguments.size + 1
              if ele.type.element_type then
                tt = ele.type.element_type[nil][-1]
              else
                tt = RubyType::BaseType.from_ruby_class(Object)
              end
              num.times do |i|
                res.push tt
              end
            end
          end

          if mt and args[1].is_a?(BlockTopNode) then
            sig =  @yield_signature_cache[cursig]
            if sig then
              args[1].type = nil
              res[1] = args[1].decide_type_once(sig)
            end
          end

          res
        end

        def extend_args(context, args)
          if is_args_splat then
            ret = args.dup
            cursig = context.to_signature
            ary = ret.pop
            tbl = {}
            ary.element_node_list.each do |type, sig, node, idxa|
              if idxa then
                idx = idxa[0]
                if sig == cursig then
                  tbl[idx] = node
                end
              end
            end

            i = 0
            while tbl[i] 
              ret.push tbl[i]
              i += 1
            end

            if i == 0 then
              # not find no element type info
              mt, slf = get_send_method_node(cursig)
              num = mt.body.argc - @arguments.size + 1
              num.times do |i|
                ret.push ary.element_node_list[0][2]
              end
            end

            ret
          else
            args
          end
        end

        def compile_c_vararg(context)
          fnc = nil
          context.start_using_reg(TMPR2)
          
          context = gen_make_argv(context) do |context, rarg|
            context.start_arg_reg
            
            context.cpustack_pushn(3 * AsmType::MACHINE_WORD.size)
            casm = context.assembler
            casm.with_retry do 
              casm.mov(FUNC_ARG[0], rarg.size) # argc
              casm.mov(FUNC_ARG[1], TMPR2)     # argv
            end
            context.set_reg_content(FUNC_ARG[0].dst_opecode, :argc)
            context.set_reg_content(FUNC_ARG[1].dst_opecode, TMPR2)

            # Method Select
            # it is legal. use TMPR2 for method select
            # use PTMPR for store self
            context = @func.compile(context)
            fnc = context.ret_reg
            casm.with_retry do 
              casm.mov(FUNC_ARG[2], context.ret_reg2)     # self
            end
            context.set_reg_content(FUNC_ARG[2].dst_opecode, context.ret_node)
            
            context = gen_save_thepr(context)
            context = gen_call(context, fnc, 3)
            context.cpustack_popn(3 * AsmType::MACHINE_WORD.size)
            context.end_arg_reg
            context.end_using_reg(TMPR2)
            context.ret_reg = RETR
            context.set_reg_content(context.ret_reg, self)
            context.ret_node = self

            @type = nil
            decide_type_once(context.to_signature)
            if !@type.boxed then
              context = @type.to_box.gen_unboxing(context)
            end
            
            context
          end
        end

        def compile_c_fixarg(context)
          fnc = nil
          numarg = @arguments.size - 2
          sig = context.to_signature
          
          context.start_arg_reg
          context.cpustack_pushn(numarg * AsmType::MACHINE_WORD.size)
          
          argpos = 0
          cursrc = 0
          casm = context.assembler
          @arguments.each do |arg|
            # skip prevenv and block_argument
            if cursrc < 2 then
              cursrc = cursrc + 1
              next
            end
            
            if cursrc == 2 then
              # Self
              # Method Select
              # it is legal. use TMPR2 for method select
              # use PTMPR for store self
              context = @func.compile(context)
              fnc = context.ret_reg
              casm.with_retry do 
                casm.mov(FUNC_ARG[0], context.ret_reg2)
              end
              context.set_reg_content(FUNC_ARG[0].dst_opecode, 
                                      context.ret_node)
            else
              # other arg.
              context = arg.compile(context)
              rnode = context.ret_node
              rtype = rnode.decide_type_once(sig)
              context = rtype.gen_boxing(context)
              casm.with_retry do 
                casm.mov(FUNC_ARG[argpos], context.ret_reg)
              end
              context.set_reg_content(FUNC_ARG[argpos].dst_opecode, 
                                      context.ret_node)
            end
            argpos = argpos + 1
            cursrc = cursrc + 1
          end
          
          context = gen_save_thepr(context)
          context = gen_call(context, fnc, numarg)
          
          context.cpustack_popn(numarg * AsmType::MACHINE_WORD.size)
          context.end_arg_reg
          context.ret_reg = RETR
          context.set_reg_content(context.ret_reg, self)
          
          decide_type_once(sig)
          if !@type.boxed then 
            context = @type.to_box.gen_unboxing(context)
          end
          
          context
        end

        def set_ensure_proc(context)
          cursig = context.to_signature
          casm = context.assembler
          # construct and set exception handler in current frame
          fstentry = nil
          if @current_exception_table then
            [:ensure].each do |kind|
              ent = nil
              if entbase = @current_exception_table[kind] then
                ent = entbase[3]
              end
              if ent then
                csadd = ent.get_code_space(cursig).var_base_immidiate_address
              else
                csadd = TopTopNode.get_nothing_proc.var_base_immidiate_address
              end
              entry = casm.add_value_entry(csadd)
              fstentry ||= entry.to_immidiate
            end
            foff = @frame_info.parent.frame_offset
            handoff = AsmType::MACHINE_WORD.size * 2 + foff
            handop = OpIndirect.new(BPR, handoff)
            casm.with_retry do
              casm.mov(TMPR, fstentry)
              casm.mov(handop, TMPR)
            end
            context.set_reg_content(handoff, :first_exception_entry)
          end
        end

        def gen_push_prev_env(context, cursig, casm)
          # push prev env
          if @func.is_a?(YieldNode) then
            prevenv = @frame_info.offset_arg(0, BPR)
            casm.with_retry do 
              casm.mov(TMPR, prevenv)
              casm.mov(FUNC_ARG_YTL[0], TMPR)
            end
            context.set_reg_content(FUNC_ARG_YTL[0].dst_opecode, prevenv)
          elsif @func.is_a?(DirectBlockNode) then
            context = @arguments[0].compile(context)
            casm.with_retry do 
              casm.mov(FUNC_ARG_YTL[0], context.ret_reg)
            end
            context.set_reg_content(FUNC_ARG_YTL[0].dst_opecode, context.ret_node)
          else
            casm.with_retry do 
              casm.mov(FUNC_ARG_YTL[0], BPR)
            end
            context.set_reg_content(FUNC_ARG_YTL[0].dst_opecode, BPR)
          end
          
          context
        end

        def gen_push_blk_slf_and_call(context, cursig, numarg, casm)
          # push block
          sig = @yield_signature_cache[cursig]
          ecs = @arguments[1].code_space_from_signature[sig]
          ecs ||= @arguments[1].code_space
          entry = ecs.var_base_immidiate_address
          casm.with_retry do 
            casm.mov(FUNC_ARG_YTL[1], entry)
          end
          context.set_reg_content(FUNC_ARG_YTL[1].dst_opecode, entry)

          # push self and call
          # Method Select
          # it is legal. use TMPR2 for method select
          # use PTMPR for store self
          context = @func.compile(context)
          fnc = context.ret_reg
          casm.with_retry do 
            casm.mov(FUNC_ARG_YTL[2], context.ret_reg2)
          end
          context.set_reg_content(FUNC_ARG_YTL[2].dst_opecode, @arguments[2])

          context = gen_save_thepr(context)
          gen_call(context, fnc, numarg)
        end

        def cmp_block(context)
          # compile block with other code space and context
          tcontext = context.dup
          tcontext.prev_context = context
          tcontext.stack_content = []
          @arguments[1].compile(tcontext)
        end

        def compile_ytl(context)
          numarg = @arguments.size
          cursig = context.to_signature
          
          context.start_arg_reg
          context.start_arg_reg(FUNC_ARG_YTL)
          context.cpustack_pushn(numarg * 8)

          casm = context.assembler
          set_ensure_proc(context)

          context = gen_push_prev_env(context, cursig, casm)
          cmp_block(context)
          
          # other arguments
          @arguments[3..-1].each_with_index do |arg, i|
            context = arg.compile(context)
            casm.with_retry do 
              casm.mov(FUNC_ARG_YTL[i + 3], context.ret_reg)
            end
            context.set_reg_content(FUNC_ARG_YTL[i + 3].dst_opecode, 
                                    context.ret_node)
          end

          context = gen_push_blk_slf_and_call(context, cursig, numarg, casm)
          
          context.cpustack_popn(numarg * 8)
          context.end_arg_reg
          context.end_arg_reg(FUNC_ARG_YTL)

          context
        end

        include UnboxedArrayUtil
        def compile_ytl_ext_ary(context)
          numarg = @arguments.size
          cursig = context.to_signature
          
          context.start_arg_reg
          context.start_arg_reg(FUNC_ARG_YTL)
          context.cpustack_pushn(numarg * 8)

          casm = context.assembler
          set_ensure_proc(context)

          context = gen_push_prev_env(context, cursig, casm)
          cmp_block(context)
          
          # other arguments
          idxbase = -1
          @arguments[3..-3].each_with_index do |arg, i|
            context = arg.compile(context)
            casm.with_retry do 
              casm.mov(FUNC_ARG_YTL[i + 3], context.ret_reg)
            end
            context.set_reg_content(FUNC_ARG_YTL[i + 3].dst_opecode, 
                                    context.ret_node)
            idxbase = i
          end

          arg = @arguments[-1]
          idxbase = idxbase + 1
          mt, slf = get_send_method_node(cursig)
          rargnum = mt.body.argc - @arguments.size + 1
          addr = lambda {
            a = address_of("rb_ary_entry")
            $symbol_table[a] = "rb_ary_entry"
            a
          }
          aref = OpVarMemAddress.new(addr)

          context = arg.compile(context)
          context.start_using_reg(TMPR2)
          casm.with_retry do 
            casm.mov(TMPR2, context.ret_reg)
          end

          rargnum.times do |i|
            casm.with_retry do 
              casm.mov(TMPR, i)
              casm.push(TMPR2)
              casm.push(TMPR)
              casm.push(TMPR2)
              casm.call(aref)
              casm.add(SPR, AsmType::MACHINE_WORD.size * 2)
              casm.pop(TMPR2)
            end
            context.ret_reg = RETR
            tt = nil
            if arg.type.element_type then
              tt = arg.type.element_type[[i]] || arg.type.element_type[nil]
              tt = tt[0]
            else
              tt = RubyType::BaseType.from_ruby_class(Object)
            end
            if !tt.boxed then
              context = tt.to_box.gen_unboxing(context)
            end
            casm.with_retry do 
              casm.mov(FUNC_ARG_YTL[idxbase + i + 3], RETR)
            end
          end
          context.end_using_reg(TMPR2)

          context = gen_push_blk_slf_and_call(context, cursig, numarg, casm)
          
          context.cpustack_popn(numarg * 8)
          context.end_arg_reg
          context.end_arg_reg(FUNC_ARG_YTL)

          context
        end

        def compile_ytl_inline(context)
          fnc = nil
          numarg = @arguments.size
          blknode = @func.block_nodes[0]
          blk_finfo = blknode.body
          
          casm = context.assembler
          set_ensure_proc(context)

          # push prev env
          # Prev env is set in toplevel
          # yield is no block
          # self is set in toplevel
          
          context = gen_save_thepr(context)
          # other arguments
          if @arguments[4] == nil then
            context = @arguments[3].compile(context)
            casm.with_retry do 
              casm.mov(TMPR, context.ret_reg)
            end
#            context.set_reg_content(argpos, context.ret_node)
          else 
            raise "Unsupport more 2 arguments in yield"
          end
          fnc = @frame_info.offset_arg(1, BPR)

          context = gen_call(context, fnc, 0)
          context
        end

        def compile_c_fixarg_raw(context)
          context = @func.compile(context)
          fnc = context.ret_reg
          numarg = @arguments.size
          
          context.start_arg_reg
          context.cpustack_pushn(numarg * AsmType::MACHINE_WORD.size)
          casm = context.assembler
          
          @arguments.each_with_index do |arg, argpos|
#            p "#{@func.name} #{argpos}"
            context = arg.compile(context)
            rtype = context.ret_node.decide_type_once(context.to_signature)

            atype = @func.arg_type[argpos]
            if atype == :"..." or atype == nil then
              if @func.arg_type.last == :"..." then
                atype = @func.arg_type[-2]
              end
            end
            if atype == :VALUE then
              context = rtype.gen_boxing(context)
            end

            casm.with_retry do 
              casm.mov(FUNC_ARG[argpos], context.ret_reg)
            end
            context.set_reg_content(FUNC_ARG[argpos].dst_opecode, 
                                    context.ret_node)
          end
          
          context = gen_save_thepr(context)
          context = gen_call(context, fnc, numarg)
          
          context.cpustack_popn(numarg * AsmType::MACHINE_WORD.size)
          context.end_arg_reg
          context.ret_reg = RETR
          context.set_reg_content(context.ret_reg, self)
          
          decide_type_once(context.to_signature)
          context
        end
      end

      module SendSingletonClassUtil
        def get_singleton_class_object(slfnode)
          tt = nil
          case slfnode
          when ConstantRefNode
            clstop = slfnode.value_node
            case clstop
            when ClassTopNode
              tt = RubyType::BaseType.from_ruby_class(clstop.klass_object)
            when LiteralNode
              tt = RubyType::BaseType.from_ruby_class(clstop.value)
            else
              raise "Unkown node type in constant #{slfnode.value_node.class}"
            end
            
          else
            raise "Unkonwn node type #{@arguments[2].class} "
          end

          tt
        end
      end

      module MultipleCodeSpaceUtil
        def find_cs_by_signature(sig)
          @code_spaces.each do |csig, val|
            if csig == sig then
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

        def get_code_space(sig)
          cs = find_cs_by_signature(sig)
          if cs == nil then
            cs = CodeSpace.new
            @code_spaces.push [sig, cs]
          end
          cs
        end
      end

      class DummyNode
        def collect_info(context)
          context
        end

        def collect_candidate_type(context)
          context
        end

        def compile(context)
          # Not need super because this is dummy
          context
        end
      end

      class TypedDummyNode<BaseNode
        include TypeListWithoutSignature
        @@node_table = {}

        def self.instance(cursig, type)
          ins = @@node_table[type]
          if ins == nil then
            ins = @@node_table[type] = TypedDummyNode.new(nil)
            ins.add_type(cursig, type)
          end

          ins
        end
      end

      # The top of top node
      class TopNode<BaseNode
        include HaveChildlenMixin
        include NodeUtil
        include MultipleCodeSpaceUtil
        
        def initialize(parent, name = nil)
          super(parent)
          @name = name
          @code_spaces = [] # [[nil, CodeSpace.new]]
          @code_space_from_signature = {}  # return type -> codespace
          @yield_node = []
          if @parent then
            @classtop = search_class_top
          else
            @classtop = self
          end
          @end_nodes = []
          @signature_cache = []
          @current_signature = []
          @exception_table = nil
          @send_nodes_with_block = nil

          @inline_block = []

          @escape_info_tab = {}
          @escape_info = nil
          @frame_offset = 0
          @compiled = false
        end

        attr_accessor :name
        attr          :code_space_from_signature
        attr          :end_nodes
        attr          :yield_node

        attr          :signature_cache
        attr          :current_signature
        attr          :classtop
        attr_accessor :exception_table

        attr          :inline_block

        attr_accessor :send_nodes_with_block
        attr          :escape_info
        attr :frame_offset

        def modified_instance_var
          search_end.modified_instance_var
        end

        def traverse_childlen
          yield @body
        end

        def add_arg_to_args(args, addnum)
          if args.is_a?(Integer) then
            args = args + addnum
          elsif args.is_a?(Array) then
            args = args.dup
            args[0] += addnum
            args[3] += addnum if args[3] >= 0
            args[4] += addnum if args[4] >= 0
            args[5] += addnum if args[5] >= 0
          else
            raise "Unkonwn args #{args}"
          end

          args
        end

        def system_num
          # 5means BP on Stack, HP, Exception Tag, BP and SP
          5
        end

        def construct_system_frame(frame_layout, curpos, finfo)
          frame_layout[curpos] = SystemValueNode.new(finfo, 
                                                     :RET_ADDR, curpos)
          curpos -= 1
          frame_layout[curpos] = SystemValueNode.new(finfo, 
                                                     :OLD_BP, curpos)
          curpos -= 1
          frame_layout[curpos] = SystemValueNode.new(finfo, 
                                                     :EXPTAG, curpos)
          curpos -= 1
          frame_layout[curpos] = SystemValueNode.new(finfo, 
                                                     :TMPHEAP, curpos)
          curpos -= 1
          frame_layout[curpos] = SystemValueNode.new(finfo, 
                                                     :OLD_BPSTACK, curpos)
        end

        def construct_frame_info(locals, argnum, args)
          finfo = LocalFrameInfoNode.new(self)
          finfo.system_num = system_num

          argc = args
          opt_label = []
          rest_index = -1
          post_len = -1
          post_start = -1
          block_index = -1
          simple = -1
          if args.is_a?(Array) then
            argc, opt_label, post_len, post_start, 
              rest_index, block_index, simple = args
            finfo.opt_label = opt_label
            finfo.post_len = post_len
            finfo.post_start = post_start
            finfo.rest_index = rest_index
            finfo.block_index = block_index
            finfo.simple = simple
          end
          finfo.argc = argc
          
          lsize = locals.size + finfo.system_num
          
          # construct frame
          frame_layout = Array.new(lsize)
          fargstart = lsize - argnum
          i = 0
          argnum.times do
            kind = :arg
            if i == rest_index then
              kind = :rest_arg
            end
            lnode = LocalVarNode.new(finfo, locals[i], fargstart + i,
                                     kind)
            frame_layout[fargstart + i] = lnode
            i = i + 1
          end

          construct_system_frame(frame_layout, fargstart - 1, finfo)

          j = 0
          lvarnum = lsize - finfo.system_num 
          while i < lvarnum do
            lnode = LocalVarNode.new(finfo, locals[i], j, :local_var)
            frame_layout[j] = lnode
            i += 1
            j += 1
          end
          finfo.frame_layout = frame_layout
          finfo.argument_num = argnum
          
          @body = finfo
          finfo.init_after_construct
          finfo
        end

        def collect_info_top(context)
          context.yield_node.push []
          context = @body.collect_info(context)
          @yield_node = context.yield_node.pop
          if @exception_table then
            @exception_table.each do |kind, lst|
              lst.each do |st, ed, cnt, body|
                if body then
                  context = body.collect_info(context)
                end
              end
            end
          end

          @inline_block.each do |btop|
            if btop.frame_offset == nil then
              finfo = btop.body
              fsize = finfo.frame_size + finfo.alloca_area_size
              btop.set_frame_offset(@body.static_alloca(fsize))
            end
          end

          context
        end

        def collect_info(context)
          collect_info_top(context)
          context
        end

        def collect_candidate_type_common(context, signode, sig)
          context.push_signature(signode, self)
          context = @body.collect_candidate_type(context)
          if @exception_table then
            @exception_table.each do |kind, lst|
              lst.each do |st, ed, cnt, body|
                if body then
                  context = body.collect_candidate_type(context)
                end
              end
            end
          end
          context.pop_signature

          @end_nodes.each do |enode|
            same_type(self, enode, sig, sig, context)
            same_type(enode, self, sig, sig, context)
          end
          @current_signature = nil
          context
        end

        def disp_signature
          tcontext = CompileContext.new(self)
          print "#{debug_info.inspect}\n"
          print "#{@classtop.klass_object}##{@name} "
          @code_spaces.each do |sig, cs|
            print sig, " -> "
            tl = type_list(sig).flatten.uniq
            print decide_type_core(tl, sig).inspect, "\n"
            pp tl
#            print "CodeSpace 0x#{cs.base_address.to_s(16)}\n"
            print "CodeSpace #{cs.inspect}\n"
          end
        end

        def gen_comment(context)
          if debug_info then
            lineno = debug_info[3]
            fname = debug_info[0]
            entry = [1, @name]
            @code_spaces.each do |sig, cs|
              ent2 = []
              ent2.push sig
              ent2.push decide_type_once(sig)
              entry.push ent2
            end

            context.comment[fname] ||= {}
            context.comment[fname][lineno] ||= []
            context.comment[fname][lineno].push entry
          end
        end

        def compile_init(context)
          context
        end

        def compile(context)
          if @compiled then
            return context
          end

          @compiled = true
          oldcs = context.code_space
          @code_spaces.each do |sig, cs|
            context.current_method_signature.push sig
            context.set_code_space(cs)
            context = super(context)
            context.reset_using_reg
            context.using_xmm_reg.push 0
            @body.frame_layout.each do |rec|
              context = rec.compile(context)
            end
            context = gen_method_prologue(context)

            context = compile_init(context)
            context = @body.compile(context)

            if @exception_table then
              @exception_table.each do |kind, lst|
                lst.each do |st, ed, cnt, body|
                  if body then
                    context = body.compile(context)
                  end
                end
              end
            end
            context.using_xmm_reg.pop

            context.current_method_signature.pop
            @code_space_from_signature[sig] = cs
          end

          if oldcs then
            context.set_code_space(oldcs)
          end

          if context.options[:disp_signature] then
            disp_signature
          end

          if context.options[:insert_signature_comment] then
            gen_comment(context)
          end

          context.ret_node = self
          context
        end
      end

      # Top of method definition
      class MethodTopNode<TopNode
        include MethodTopCodeGen

        def collect_info(context)
          context.modified_local_var.push [{}]
          context = super
          context.modified_local_var.pop
          context
        end

        def apply_escape_info_to_args(signode)
          @escape_info.each_with_index do |val, idx|
            if val and idx != 2 then
              signode[idx].set_escape_node_backward(val)
            end
          end
        end

        def collect_candidate_type(context, signode, sig)
          @current_signature = nil
          @escape_info_tab[signode[0]] ||= []
          @escape_info = @escape_info_tab[signode[0]]
          context.visited_top_node[self] ||= []
          apply_escape_info_to_args(signode)
          if add_cs_for_signature(sig) == nil and  
              context.visited_top_node[self].include?(sig) then
            return context
          end

          @current_signature = sig
          context.visited_top_node[self].push sig

          if !@signature_cache.include?(sig) then
            @signature_cache.push sig
          end

          context = collect_candidate_type_common(context, signode, sig)
          @escape_info = nil
          context
        end

        def construct_frame_info(locals, argnum, args)
          locals.unshift :_self
          locals.unshift :_block
          locals.unshift :_prev_env
          argnum += 3
          args = add_arg_to_args(args, 3)
          super(locals, argnum, args)
        end
      end

      class BlockTopNode<MethodTopNode
        def collect_info(context)
          context.modified_local_var.last.push Hash.new
          context = collect_info_top(context)
          context.modified_local_var.last.pop
          context
        end

        include MethodTopCodeGen
      end

      class BlockTopInlineNode<BlockTopNode
        include MethodTopCodeGen

        def initialize(parent, name = nil)
          super(parent, name)
          @frame_offset = nil # reset nil for check set
        end

        def set_frame_offset(raw_offset)
          @frame_offset = raw_offset + 
            (@body.local_area_size + @body.alloca_area_size)
        end

        def system_num
          3
        end

        def construct_system_frame(frame_layout, curpos, finfo)
          frame_layout[curpos] = SystemValueNode.new(finfo, 
                                                     :EXPTAG, curpos)
          curpos -= 1
          frame_layout[curpos] = SystemValueNode.new(finfo, 
                                                     :TMPHEAP, curpos)
          curpos -= 1
          frame_layout[curpos] = SystemValueNode.new(finfo, 
                                                     :OLD_SP, curpos)
        end

        def gen_method_prologue(context)
          asm = context.assembler

          # Make linkage of frame pointer
          # One argument pass by TMPR
          arg0 = @body.offset_arg(3, BPR)
          savesp = OpIndirect.new(BPR, @frame_offset)
 
          asm.with_retry do
            asm.push(BPR)
            asm.mov(BPR, INDIRECT_BPR)
            asm.mov(BPR, INDIRECT_BPR)
            asm.mov(savesp, SPR)
            asm.mov(arg0, TMPR)
          end
          context.cpustack_push(BPR)
          context.set_reg_content(BPR, :frame_ptr)
            
          context
        end
      end

      class ClassTopNode<TopNode
        include SendNodeCodeGen
        include MethodTopCodeGen
        @@class_top_tab = {}

        def self.get_class_top_node(klass)
          @@class_top_tab[klass]
        end

        def initialize(parent, klassobj, name = nil)
          super(parent, name)
          @before_search_module = []
          @after_search_module = []
          @constant_tab = {}
          @method_tab = {}
          @klass_object = klassobj
          @klassclass = ClassClassWrapper.instance(@klass_object)
          @klassclass_node = nil # Lazy
          RubyType::define_wraped_class(@klassclass, 
                                        RubyType::RubyTypeBoxed)
          unless @@class_top_tab[klassobj]
            @@class_top_tab[klassobj] = self
          end
        end

        attr :klass_object
        attr :constant_tab
        attr :method_tab
        attr :klassclass
        attr :klassclass_node
        attr :before_search_module
        attr :after_search_module

        def collect_info(context)
          context.modified_local_var.push [{}]
          context.modified_instance_var = Hash.new
          context = super
          context.modified_local_var.pop
          if @klassclass_node then
            @klassclass_node.collect_info(context)
          else
            context
          end
        end

        def make_klassclass_node
          if @klassclass_node == nil then
            clsclsnode = ClassTopNode.new(self, 
                                          @klassclass, 
                                          @klassclass.name)
            clsclsnode.body = DummyNode.new
            @klassclass_node = clsclsnode
          end
          @klassclass_node
        end

        def get_method_tab(klassobj = @klass_object)
          ktop =  @@class_top_tab[klassobj]
          if ktop then
            ktop.method_tab
          else
            {}
          end
        end

        def get_constant_tab(klassobj = @klass_object)
          ktop =  @@class_top_tab[klassobj]
          if ktop then
            ktop.constant_tab
          else
            ktop.constant_tab = {}
            ktop.constant_tab
          end
        end

        def add_before_search_module(scope, mod)
          clsnode = @@class_top_tab[@klass_object]
          clsnode.before_search_module.each do |scope, modnode|
            if modnode == mod then
              return
            end
          end
          clsnode.before_search_module.push [scope, mod]
        end

        def add_after_search_module(scope, mod)
          clsnode = @@class_top_tab[@klass_object]
          clsnode.after_search_module.each do |scope, modnode|
            if modnode == mod then
              return
            end
          end
          clsnode.before_search_module.unshift [scope, mod]
        end

        def search_method_with_super(name, klassobj = @klass_object)
          clsnode = @@class_top_tab[klassobj]
          if clsnode then
            clsnode.before_search_module.each do |scope, mod|
              mtab = mod.get_method_tab
              if val = mtab[name] then
                return [val, mod]
              end
            end

            mtab = clsnode.get_method_tab
            if val = mtab[name] then
              return [val, clsnode]
            end

            clsnode.after_search_module.each do |scope, mod|
              mtab = mod.get_method_tab
              if val = mtab[name] then
                return [val, mod]
              end
            end

            if klassobj.is_a?(Class) then
              return search_method_with_super(name, klassobj.superclass)
            else
              # klassobj is Module
              return search_method_with_super(name, Object)
            end
          end

          [nil, nil]
        end

        def search_constant_with_super(name, klassobj = @klass_object)
          clsnode = @@class_top_tab[klassobj]
          while clsnode
            klassobj = clsnode.klass_object
            clsnode.before_search_module.each do |scope, mod|
              ctab = mod.get_constant_tab
              if val = ctab[name] then
                return [val, mod]
              end
            end

            ctab = clsnode.get_constant_tab
            if val = ctab[name] then
              return [val, clsnode]
            end

            if klassobj.is_a?(Class) then
              res = search_constant_with_super(name, klassobj.superclass)
              if res[1] then
                return res
              end
            end

            begin
              clsnode = clsnode.parent
            end while clsnode and !clsnode.is_a?(ClassTopNode)
          end

          [nil, nil]
        end

        def construct_frame_info(locals, argnum, args)
          locals.unshift :_self
          locals.unshift :_block
          locals.unshift :_prev_env
          argnum += 3
          args = add_arg_to_args(args, 3)
          super(locals, argnum, args)
        end

        def collect_candidate_type(context, signode, sig)
          @current_signature = nil
          @type = RubyType::BaseType.from_ruby_class(@klassclass)
          add_type(sig, @type)
          context.visited_top_node[self] ||= []

          if add_cs_for_signature(sig) == nil and  
              context.visited_top_node[self].include?(sig) then
            return context
          end

          @current_signature = sig
          context.visited_top_node[self].push sig
          if !@signature_cache.include?(sig) then
            @signature_cache.push sig
          end
          
          context.push_signature(signode, self)
          context = @body.collect_candidate_type(context)
          context.pop_signature

          if @klassclass_node then
            context = @klassclass_node.collect_candidate_type(context, 
                                                              signode, sig)
          end

          set_escape_node(:not_export)
          @current_signature = nil

          context
        end

        def compile(context)
          context = super(context)

          sig = context.to_signature.dup
          sig[2] = @type
=begin
          pp sig
          pp @name
          pp @code_spaces.map{|a| a[0]}
=end

          cs = self.find_cs_by_signature(sig)
          if cs then
            asm = context.assembler
            add = lambda { @klass_object.address }
            var_klassclass = OpVarImmidiateAddress.new(add)
            context.start_arg_reg
            asm.with_retry do
              asm.mov(FUNC_ARG_YTL[0], BPR)
              asm.mov(FUNC_ARG_YTL[1], 4)
              asm.mov(FUNC_ARG_YTL[2], var_klassclass)
            end
            context.set_reg_content(FUNC_ARG_YTL[0].dst_opecode, BPR)
            context.set_reg_content(FUNC_ARG_YTL[1].dst_opecode, true)
            context.set_reg_content(FUNC_ARG_YTL[2].dst_opecode, self)
            add = cs.var_base_address
            context = gen_save_thepr(context)
            context = gen_call(context, add, 3)
            context.end_arg_reg
          end
          
          context
        end

        def get_constant_value
          [@klass_object]
        end
      end

      class TopTopNode<ClassTopNode
        include MethodTopCodeGen
        @@frame_struct_tab = {}
        @@local_object_area = Runtime::Arena.new
        @@global_object_area = Runtime::Arena.new
        @@unwind_proc = CodeSpace.new
        @@nothing_proc = CodeSpace.new

        def self.get_frame_struct_tab
          @@frame_struct_tab
        end

        def self.get_unwind_proc
          @@unwind_proc
        end


        def self.get_nothing_proc
          @@nothing_proc
        end

        def initialize(parent, klassobj, name = :top)
          super
          
          @code_space_tab = []
          @asm_tab = {}
          @id.push 0

          @frame_struct_array = []
          @init_node = nil

          # Dummy for marshal
          @op_var_value_instaces = nil

          @modified_global_var = nil
        end

        attr_accessor :init_node
        attr          :code_space_tab
        attr          :asm_tab
        attr          :frame_struct_array

        def make_frame_struct_tab
          @frame_struct_array.each do |vkey, val|
            @@frame_struct_tab[vkey.value] = val
          end
        end

        def traverse_childlen
          if @init_node then
            yield @init_node
          end
          yield @body
        end

        def init_unwind_proc
          asm = Assembler.new(@@unwind_proc)
          # Make linkage of frame pointer
          asm.with_retry do
            asm.mov(SPR, BPR)
            asm.pop(BPR)
            # must be asm.pop(THEPR)? Maybe not because release caller
            asm.pop(TMPR)   # Dummy pop THEPR
            asm.pop(TMPR2)   # exception handler
            asm.mov(SPR, BPR)
            asm.pop(BPR) # Return address store by call inst.
            asm.pop(TMPR) # return address
            asm.add(TMPR2, TMPR3)  # TMPR3 store offset of exception handler
            asm.mov(TMPR2, INDIRECT_TMPR2)
            asm.and(TMPR2, TMPR2)
            asm.jz(@@unwind_proc.var_base_address)
            asm.jmp(TMPR2)
          end

          asm = Assembler.new(@@nothing_proc)
          # Make linkage of frame pointer
          asm.with_retry do
            asm.ret
          end
        end
        
        def add_code_space(oldcs, newcs)
          if !@code_space_tab.include?(newcs) then
            @code_space_tab.push newcs
          end
        end

        def collect_info(context)
          if @init_node then
            context = @init_node.collect_info(context)
          else
            init_unwind_proc
            add_code_space(nil, @@unwind_proc)
          end
          context = super
          @modified_global_var = context.modified_global_var
          context
        end

        def collect_candidate_type(context, signode, sig)
          context.convergent = true
          context.visited_top_node = {}
          if @init_node then
            context = @init_node.collect_candidate_type(context, signode, sig)
          end

          # This is for return boxed object to CRuby system
          if @end_nodes[0] then
            @end_nodes[0].add_type(sig, RubyType::BaseType.from_object(nil))
          end

          super(context, signode, sig)
        end

        def get_global_object_area
          @@global_object_area
        end
        
        def get_global_arena_address
          ar = @@global_object_area
          addr = lambda {
            ar.raw_address
          }
          OpVarImmidiateAddress.new(addr)           
        end

        def get_global_arena_end_address
          ar = @@global_object_area
          addr = lambda {
            ar.body_address + ar.size
          }
          OpVarImmidiateAddress.new(addr)           
        end

        def get_local_arena_address
          ar = @@local_object_area
          addr = lambda {
            ar.raw_address
          }
          OpVarImmidiateAddress.new(addr)           
        end

        def get_local_arena_end_address
          ar = @@local_object_area
          addr = lambda {
            (ar.body_address + ar.size) & (~0xf)
          }
          OpVarImmidiateAddress.new(addr)           
        end

        def compile_init(context)
          asm = context.assembler
          asm.with_retry do
            asm.mov(THEPR, get_local_arena_end_address)
          end
          context
        end

        def compile(context)
          if @init_node then
            context = @init_node.compile(context)
          end
          @modified_global_var.each_with_index do |dmy, i|
            @@global_object_area[i + 1] = 4
=begin
            p @@global_object_area
            p dmy[0]
=end
          end
          super(context)
        end

        def code_store_hook
          @op_var_value_instaces = OpVarValueMixin.instances
        end

        def update_after_restore
          @op_var_value_instaces.each do |ins|
            ins.refer.each do |stfn|
              stfn.call
            end
          end
        end
      end

      class ExceptionTopNode<TopNode
        include HaveChildlenMixin
        include NodeUtil
        include MultipleCodeSpaceUtil
        include MethodEndCodeGen

        def initialize(parent, name = nil)
          super
          @code_spaces = []
        end

        def collect_info(context)
          @body.collect_info(context)
        end

        def collect_candidate_type(context)
          @body.collect_candidate_type(context)
        end

        def compile(context)
          sig = context.to_signature
          cs = get_code_space(sig)
          oldcs = context.set_code_space(cs)
          context = @body.compile(context)
          asm = context.assembler
          asm.with_retry do
            asm.ret
          end
          context.set_code_space(oldcs)
          context
        end
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
          @local_area_size = nil
          @alloca_area_size = 0

          @argc = nil
          @opt_label = []
          @opt_label_node = []
          @post_len = nil
          @post_start = nil
          @rest_index = nil
          @block_index = nil
          @simple = true
        end

        def init_after_construct
          @local_area_size = compute_local_area_size
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
        attr          :local_area_size
        attr          :alloca_area_size

        attr_accessor :argc
        attr_accessor :opt_label
        attr_accessor :opt_label_node
        attr_accessor :post_len
        attr_accessor :post_start
        attr_accessor :rest_index
        attr_accessor :block_index
        attr_accessor :simple

        def traverse_childlen
          @frame_layout.each do |vinf|
            yield vinf
          end
          yield @body
        end

        def frame_size
          @frame_layout.inject(0) {|sum, slot| sum += slot.size}
        end

        def compute_local_area_size
          localnum = @frame_layout.size - @argument_num - @system_num
          @frame_layout[0, localnum].inject(0) {|sum, slot| 
            sum += slot.size
          }
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
 
          obyte - @local_area_size + @parent.frame_offset
        end

        def gen_operand(basereg, off)
          off = real_offset(off)

          obyte = 0
          off.times do |i|
            obyte += @frame_layout[i].size
          end
 
          roff = obyte - @local_area_size + @parent.frame_offset
          varnode =  @frame_layout[off]
          cpureg = varnode.cpu_reg
          if cpureg then
            cpureg
          else
            OpIndirect.new(basereg, roff)
          end
        end

        def offset_arg(n, basereg)
          rc = nil
          if basereg == BPR then
            rc = @offset_cache[n]
            unless rc
              rc = @offset_cache[n] = gen_operand(basereg, n)
            end
          else
            off = offset_by_byte(n)
            rc = OpIndirect.new(basereg, off)
          end

          rc
        end

        def static_alloca(size)
#          base = -offset_by_byte(0)
          @alloca_area_size += size
          -(@local_area_size + @alloca_area_size)
        end

        def collect_candidate_type(context)
          traverse_childlen {|rec|
            context = rec.collect_candidate_type(context)
          }
        end

        def compile(context)
          context = super(context)
          siz = @local_area_size + @alloca_area_size
          if siz == 0 or
              @parent.is_a?(ExceptionTopNode) or
              @parent.is_a?(BlockTopInlineNode) then
            context = @body.compile(context)

          else
            # Normal route
            asm = context.assembler
            asm.with_retry do
              asm.sub(SPR, siz)
            end
            context.cpustack_pushn(siz)
            context = @body.compile(context)
            context.cpustack_popn(siz)
          end

          context
        end
      end

      class LocalVarNode<BaseNode
        include AbsArch
        
        def initialize(parent, name, offset, kind)
          super(parent)
          @name = name
          @offset = offset
          @kind = kind
          @cpu_reg = nil
          @export_block = false
        end

        attr          :name
        attr          :kind
        attr_accessor :cpu_reg
        attr_accessor :export_block

        def size
          8
        end

        def collect_info(context)
          flay = @parent.frame_layout
          fragstart = flay.size - @parent.argument_num
          if fragstart <= @offset then
            argoff = @offset - fragstart
          else
            argoff = @offset + @parent.argument_num
          end
=begin
          # Assertion check for reverse of real_offset
          unless @offset == @parent.real_offset(argoff)
            raise
          end
=end
          topnode = @parent.parent
          context.modified_local_var.last.last[argoff] = [[topnode, self]]
          context
        end

        def collect_candidate_type(context)
          flay = @parent.frame_layout
          fragstart = flay.size - @parent.argument_num
          if fragstart <= @offset then
            argoff = @offset - fragstart
            tobj = context.current_method_signature_node.last[argoff]
            if tobj then
              cursig = context.to_signature
              cursig2 = context.to_signature(-2)
              same_type(self, tobj, cursig, cursig2, context)
              # same_type(tobj, self, cursig2, cursig, context)
            end
          end
          context
        end

        def set_escape_node(value)
          topnode = @parent.parent
          if topnode.escape_info then
            flay = @parent.frame_layout
            fragstart = flay.size - @parent.argument_num
            if fragstart <= @offset then
              argoff = @offset - fragstart
              @is_escape = topnode.escape_info[argoff]
              super(value)
              topnode.escape_info[argoff] = @is_escape
            else
              super(value)
            end
          else
            super(value)
          end
        end

        def compile(context)
          context = super(context)
          cursig = context.to_signature
          rtype = decide_type_once(cursig)
          if rtype.ruby_type == Float and !rtype.boxed and 
              !@export_block and
              context.using_xmm_reg.last < 4 and 
              @kind == :local_var then
            @cpu_reg = XMM_REGVAR_TAB[context.using_xmm_reg.last]
            context.using_xmm_reg[-1] += 1
          end
          context
        end
      end

      class SystemValueNode<BaseNode
        def initialize(parent, kind, offset)
          super(parent)
          @kind = kind
          @offset = offset
          @cpu_reg = nil
        end

        attr :offset
        attr :name
        attr_accessor :cpu_reg

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
          @modified_instance_var = context.modified_instance_var
          context
        end

        def collect_candidate_type(context)
          cursig = context.to_signature
          same_type(self, @parent, cursig, cursig, context)
          same_type(@parent, self, cursig, cursig, context)
          context
        end

        def compile_main(context)
          context = gen_method_epilogue(context)
          curas = context.assembler
          curas.with_retry do
            curas.ret
          end
          context
        end

        def compile(context)
          context = super(context)
          if context.options[:insert_signature_comment] then
            lineno = debug_info[3] + 1
            fname = debug_info[0]
            context.comment[fname] ||= {}
            context.comment[fname][lineno] ||= []
            ent = []
            ent.push 3
            ent.push @is_escape
            context.comment[fname][lineno].push ent
          end
          compile_main(context)
        end
      end

      class BlockEndNode<MethodEndNode
        include MethodEndCodeGen
      end

      class BlockEndInlineNode<BlockEndNode
        include MethodEndCodeGen
        include NodeUtil

        def initialize(parent)
          super
          @top_node = search_top
        end

        def gen_method_epilogue(context)
          asm = context.assembler
          savesp = OpIndirect.new(BPR, @top_node.frame_offset)
          asm.with_retry do
            # it can't keep stack consistency
            asm.mov(SPR, savesp)
            asm.pop(BPR)
          end
          context.stack_content = []

          context
        end

        def compile_main(context)
          asm = context.assembler
          asm.with_retry do
            # not need adjust SPR because it keeps stack consistency
            # when this code executes
            asm.pop(BPR)
            asm.ret
          end
          context
        end
      end

      class ClassEndNode<MethodEndNode
        include MethodEndCodeGen

        def initialize(parent)
          super(parent)
          @modified_instance_var = nil
        end

        attr :modified_instance_var

        def collect_info(context)
          @modified_instance_var = context.modified_instance_var
          context
        end
      end

      # Set result of method/block
      class SetResultNode<BaseNode
        include NodeUtil
        include HaveChildlenMixin

        def initialize(parent, valnode)
          super(parent)
          @value_node = valnode
          @class_top_node = search_class_top
        end

        attr :value_node

        def traverse_childlen
          yield @value_node
          yield @body
        end

        def collect_candidate_type(context)
          cursig = context.to_signature
          context = @value_node.collect_candidate_type(context)
          same_type(self, @value_node, cursig, cursig, context)
          same_type(@value_node, self, cursig, cursig, context)

#          @type = nil
          rtype = decide_type_once(cursig)
          rrtype = rtype.ruby_type
          if !rtype.boxed and rrtype != Fixnum and rrtype != Float then
            set_escape_node_backward(:local_export)
          else
            set_escape_node_backward(:not_export)
          end
          @body.collect_candidate_type(context)
        end

        def compile(context)
          context = super(context)
          context = @value_node.compile(context)
          if context.ret_reg != RETR then
            if context.ret_reg.is_a?(OpRegXMM) then
=begin
                 decide_type_once(context.to_signature)
                 context = @type.gen_boxing(context)
                 if context.ret_reg != RETR then
                   curas = context.assembler
                   curas.with_retry do
                    curas.mov(RETR, context.ret_reg)
                  end
                   
                   context.set_reg_content(RETR, context.ret_node)
                 end
=end
              context.set_reg_content(context.ret_reg, context.ret_node)
            else
              curas = context.assembler
              curas.with_retry do
                curas.mov(RETR, context.ret_reg)
              end
              context.set_reg_content(RETR, context.ret_node)
              context.ret_reg = RETR
            end
          else
            context.set_reg_content(RETR, context.ret_node)
            context.ret_reg = RETR
          end

          @body.compile(context)
        end
      end

      class PhiNode<BaseNode
        def initialize(parent)
          super(parent)
          @local_label = parent
        end
        
        def collect_candidate_type(context)
          cursig = context.to_signature
          @local_label.come_from.values.each do |vnode|
            if vnode then
              same_type(self, vnode, cursig, cursig, context)
            end
          end
          context
        end

        def compile(context)
          context = super(context)
          context.ret_node = self
          context.ret_reg = @local_label.res_area
          context
        end
      end

      class LocalLabel<BaseNode
        include HaveChildlenMixin
        include NodeUtil
        include MultipleCodeSpaceUtil

        def initialize(parent, name)
          super(parent)
          @name = name
          @come_from = {}
          @come_from_val = []
          @current_signature = nil
          @code_spaces = []
          @value_node = nil
          @modified_local_var_list = []
          @raw_offset = nil
          @res_area = nil
        end

        attr          :name
        attr          :come_from
        attr_accessor :value_node
        attr          :res_area

        def traverse_childlen
          yield @value_node
          yield @body
        end

        def lonly_node(node)
          while !node.is_a?(TopNode) 
            if node.is_a?(LocalLabel) then
              if node.come_from.size == 0 then
                return true
              else
                return false
              end
            end

            node = node.parent
          end

          return false
        end

        def collect_info(context)
          if @modified_local_var_list.size == 0 then
            # first visit
            delnode = []
            fornode = []
            @come_from.keys.each do |ele|
              if lonly_node(ele) then
                delnode.push ele
              end
            end
            delnode.each do |ele|
              @come_from.delete(ele)
            end
          end
            
          modlocvar = context.modified_local_var.last.map {|ele| ele.dup}
          @modified_local_var_list.push modlocvar
          if @modified_local_var_list.size == 1 then
            frame_node = search_frame_info
            @raw_offset = frame_node.static_alloca(8)
            @body.collect_info(context)
          elsif @modified_local_var_list.size == @come_from.size then
            context.merge_local_var(@modified_local_var_list)
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
              asm.with_retry do
                asm.mov(TMPR, context.ret_reg)
                asm.mov(@res_area, TMPR)
              end
              context.ret_reg = TMPR
            end
          end

          context.set_reg_content(context.ret_reg, self)
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
          if @res_area == nil then
            tnode = search_top
            @res_area = OpIndirect.new(BPR, @raw_offset + tnode.frame_offset)
          end
          if @come_from.keys[0] == sender then
             @body.collect_candidate_type(context)
          else
            context
          end
       end

        def compile(context)
          context = super(context)
          if @current_signature == nil or
              @current_signature != context.to_signature then
            @come_from_val = []
            @current_signature = context.to_signature
          end

          @come_from_val.push context.ret_reg
          
          if @come_from_val.size == 1 then
            @body.compile(context)
          else
            context
          end
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

        def branch(as, address, cond)
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
          sig = context.to_signature
          context = super(context)
          context = @jmp_to_node.compile_block_value(context, self)
          jmptocs = @jmp_to_node.get_code_space(sig)

          curas = context.assembler
          context = @cond.compile(context)

          cnd = context.ret_reg
          if cnd.is_a?(Fixnum) then
            cnd = cnd & (~4)
          else
            curas.with_retry do
              if context.ret_reg != TMPR then
                curas.mov(TMPR, context.ret_reg)
              end
              
              # In 64bit mode. It will be sign extended to 64 bit
              curas.and(TMPR, OpImmidiate32.new(~4))
            end
          end

          curas.with_retry do
            branch(curas, jmptocs.var_base_address, cnd)
          end

          context = @body.compile(context)
          oldcs = context.set_code_space(jmptocs)
          context = @jmp_to_node.compile(context)
#          context.set_code_space(oldcs)

          context
        end
      end

      class BranchIfNode<BranchCommonNode
        def branch(as, address, cond)
          if cond.is_a?(Fixnum) then
            if cond != 0 then
              as.jmp(address)
            end
          else
            as.jnz(address)
          end
        end
      end

      class BranchUnlessNode<BranchCommonNode
        def branch(as, address, cond)
          if cond.is_a?(Fixnum) then
            if cond == 0 then
              as.jmp(address)
            end
          else
            as.jz(address)
          end
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
          sig = context.to_signature
          context = super(context)
          context = @jmp_to_node.compile_block_value(context, self)
          if @jmp_to_node.come_from.size > 1 then
            # Jump to shared label
            jmptocs = @jmp_to_node.get_code_space(sig)
            
            curas = context.assembler
            curas.with_retry do
              curas.jmp(jmptocs.var_base_address)
              curas.ud2   # Maybe no means but this line may be useful
            end
            
            oldcs = context.set_code_space(jmptocs)
            context = @jmp_to_node.compile(context)
            context.set_code_space(oldcs)
          else
            context = @jmp_to_node.compile(context)
          end

          context
        end
      end

      class ThrowNode<BaseNode
        include HaveChildlenMixin
        include MethodEndCodeGen
        include NodeUtil

        def initialize(parent, state, exceptobj)
          super(parent)
          @curtop = search_top
          @state = state
          @exception_object = exceptobj
        end

        def traverse_childlen
          yield @exception_object
        end

        def collect_info(context)
          @exception_object.collect_info(context)
        end

        def collect_candidate_type(context)
          @exception_object.collect_candidate_type(context)
        end

        def compile_unwind(context)
          asm = context.assembler
          handoff = AsmType::MACHINE_WORD.size * 2
          handop = OpIndirect.new(BPR, handoff)
          ensureop = OpIndirect.new(TMPR, 0)
          asm.with_retry do
            asm.push(TMPR)
            asm.mov(TMPR, handop)
            asm.call(ensureop)
            asm.pop(TMPR)
          end
          gen_method_epilogue(context)
        end

        def compile(context)
          asm = context.assembler
          if @state == 0 then
            context = @exception_object.compile(context)
            
          elsif @state == 2 then # break
            context = @exception_object.compile(context)
            if context.ret_reg != TMPR then
              asm.with_retry do
                asm.mov(TMPR, context.ret_reg)                
              end
            end
            context.set_reg_content(RETR, context.ret_node)
            # two epilogue means block and method which is called with block
            context = @curtop.end_nodes[0].gen_method_epilogue(context)
            # compile_unwind is basically same as gen_method_epilogue
            # instead of gen_method_epilogue because may need to ensure proc.
            context = compile_unwind(context)
            asm.with_retry do
              asm.ret
            end

          elsif @state == 1 then # return
            context = @exception_object.compile(context)
            if context.ret_reg != TMPR then
              asm.with_retry do
                asm.mov(TMPR, context.ret_reg)                
              end
            end
            context.set_reg_content(RETR, context.ret_node)
            finfo = search_frame_info
            while finfo.parent.is_a?(BlockTopNode)
              # two epilogue means block and method which is called with block
              # compile_unwind is basically same as gen_method_epilogue
              context = finfo.parent.end_nodes[0].gen_method_epilogue(context)
              context = compile_unwind(context)
              finfo = finfo.previous_frame
            end
            context = compile_unwind(context)
            asm.with_retry do
              asm.ret
            end
          end
          context
        end
      end

      # Holder of Nodes Assign. These assignes execute parallel potencially.
      class LetNode<BaseNode
        include HaveChildlenMixin
      end

      # Holder of MultiplexNode
      class MultiplexHolderNode<BaseNode
        include HaveChildlenMixin

        def initialize(parent, node)
          super(parent)
          @mult = node
        end

        def traverse_childlen
          yield @mult
        end

        def collect_info(context)
          context = @mult.collect_info(context)
          @body.collect_info(context)
        end

        def collect_candidate_type(context)
          context = @mult.collect_candidate_type(context)
          @body.collect_candidate_type(context)
        end

        def compile(context)
          context = @mult.compile(context)
          @body.compile(context)
        end
      end

      # Multiplexer of node (Using YARV stack operation)
      class MultiplexNode<BaseNode
        include HaveChildlenMixin
        include NodeUtil

        def initialize(parent, node)
          super(parent)
          @node = node
          @compiled_by_signature = []
          @raw_offset = nil
          @res_area = nil
        end

        attr :node

        def traverse_childlen
          yield @node
        end

        def collect_info(context)
          frame_node = search_frame_info
          @raw_offset = frame_node.static_alloca(8)
          @node.collect_info(context)
        end

        def collect_candidate_type(context)
          if @res_area == nil then
            tnode = search_top
            @res_area = OpIndirect.new(BPR, @raw_offset + tnode.frame_offset)
          end
          sig = context.to_signature          
          same_type(self, @node, sig, sig, context)
          same_type(@node, self, sig, sig, context)
          @node.collect_candidate_type(context)
        end

        def compile(context)
          sig = context.to_signature
          if !@compiled_by_signature.include?(sig) then
            context = @node.compile(context)
            asm = context.assembler
            if context.ret_reg.is_a?(OpRegistor) then
              asm.with_retry do
                asm.mov(@res_area, context.ret_reg)
              end
              context.set_reg_content(@res_area, context.ret_node)
            else
              asm.with_retry do
                asm.mov(TMPR, context.ret_reg)
                asm.mov(@res_area, TMPR)
              end
              context.set_reg_content(@res_area, context.ret_node)
            end
            context.set_reg_content(@res_area, self)
            @compiled_by_signature.push sig
          else
            asm = context.assembler
            rtype = decide_type_once(sig)
            if rtype.ruby_type == Float and !rtype.boxed then
              asm.with_retry do
                asm.movsd(XMM0, @res_area)
              end
              context.set_reg_content(XMM0, self)
              context.ret_reg = XMM0
            else
              asm.with_retry do
                asm.mov(RETR, @res_area)
              end
              context.set_reg_content(RETR, self)
              context.ret_reg = RETR
            end
            context.ret_node = self
          end

          context
        end
      end

      # Literal
      class LiteralNode<BaseNode
        include NodeUtil
        include TypeListWithoutSignature

        def initialize(parent, val)
          super(parent)
          @value = val
          @type = RubyType::BaseType.from_object(val)
        end
        
        attr :value

        # Dummy for pass as block (nil)
        def code_space_from_signature
          {}
        end

        def collect_candidate_type(context)
          sig = context.to_signature
          if @type == nil then
            @type = RubyType::BaseType.from_object(@value) 
          end

          case @value
          when Array
            add_type(sig, @type)
            @value.each_with_index do |ele, i|
              etype = RubyType::BaseType.from_object(ele)
              @element_node_list[0][2].add_type(sig, etype)
              dmy = BaseNode.new(self)
              dmy.add_type(sig, etype)
              @element_node_list.push [@type, sig, dmy, [i]]
            end

          when Hash
            add_type(sig, @type)
            @value.each do |key, value|
              vtype = RubyType::BaseType.from_object(value)
              @element_node_list[0][2].add_type(sig, vtype)
            end

          when Range
            @type = @type.to_box
            add_type(sig, @type)
            if @type.args == nil then
              @type.args = []
              ele = @value.first
              fstnode = LiteralNode.new(self, ele)
              context = fstnode.collect_candidate_type(context)
              @type.args.push fstnode
              ele = @value.last
              sndnode = LiteralNode.new(self, ele)
              @type.args.push sndnode
              context = sndnode.collect_candidate_type(context)
              ele = @value.exclude_end?
              exclnode = LiteralNode.new(self, ele)
              @type.args.push exclnode
              context = exclnode.collect_candidate_type(context)
              add_element_node(@type, sig, fstnode, [0], context)
              add_element_node(@type, sig, sndnode, [1], context)
            end
          else
            add_type(sig, @type)
          end

          context
        end

        def compile_get_constant(context)
          compile(context)
        end

        def compile(context)
          context = super(context)

          decide_type_once(context.to_signature)
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
              asm = context.assembler
              valproc = lambda { 
                val.unboxing
              }
              litval = OpVarImmidiate64.new(valproc)
              litent = asm.add_value_entry(litval)
              asm.with_retry do
                asm.mov(TMPR, litent.to_immidiate)
                asm.mov(XMM0, INDIRECT_TMPR)
              end
#              context.ret_reg = INDIRECT_TMPR
              context.ret_reg = XMM0
            end
            context.ret_node = self
            context.set_reg_content(context.ret_reg, self)

          else
            if @var_value == nil then
              add = lambda { @value.address }
              @var_value = OpVarImmidiateAddress.new(add)
            end

            context.ret_node = self
            context.ret_reg = @var_value
            context = @type.gen_copy(context)
            context.set_reg_content(context.ret_reg, self)
          end

          context
        end

        def get_constant_value
          [@value]
        end

        def type=(val)
          val
        end
      end

      class TraceNode<BaseNode
        include HaveChildlenMixin
        include X86
        include AbsArch
        @@max_trace_no = 0
        @@trace_node_tab = []

        def self.prof_disp(fn, pa)
          tot = {}
          @@trace_node_tab.each do |tobj|
            a = tobj.inspect_profile_info
            a[4] = 0 if a[4] == nil
            a[5] = 0 if a[5] == nil
            if a[0] == fn then
              ln = a[3] - 1
              if tot[ln] then
                tot[ln][0] += a[4]
                tot[ln][1] += a[5]
              else
                tot[ln] = [a[4], a[5]]
              end
            end
          end

          pa.each_with_index do |l, i|
            if tot[i] then
              if tot[i][0] != 0 then
                STDERR.printf "%7d %10d ", tot[i][0], tot[i][1] / tot[i][0]
              else
                STDERR.printf "%7d %10d ", tot[i][0], tot[i][1]
              end
            else
              STDERR.print " " * 19
            end
            STDERR.print l
            STDERR.print "\n"
          end
        end

        def initialize(parent, kind)
          super(parent)
          @trace_no = @@max_trace_no
          @@trace_node_tab[@trace_no] = self
          @@max_trace_no += 1
          @kind = kind
          @cnt_offset = nil
          @time_offset = nil
          @top_node = nil
        end

        def inspect_profile_info
          if @top_node then
            oarea = @top_node.get_global_object_area
            res = debug_info.dup
            res << oarea[@cnt_offset]
            res << oarea[@time_offset]
          else
            debug_info.dup
          end
        end

        def traverse_childlen
          yield @body
        end

        def collect_info(context)
          if context.options[:profile_mode] then
            tv = "_trace_cnt#{@trace_no}".to_sym
            context.modified_global_var[tv] ||= []
            tv = "_trace_time#{@trace_no}".to_sym
            context.modified_global_var[tv] ||= []
            if @cnt_offset == nil then
              @cnt_offset = context.modified_global_var.keys.size - 1
              @time_offset = @cnt_offset + 1
            end
          end
          @body.collect_info(context)
        end
        
        def collect_candidate_type(context)
          cursig = context.to_signature
          same_type(self, @parent, cursig, cursig, context)
          @body.collect_candidate_type(context)
        end

        def compile(context)
          context = super(context)
          asm = context.assembler
          case @kind 
          when 0
            @top_node = context.top_node
            oarea = @top_node.get_global_object_area
            oarea[@cnt_offset] = 0
            oarea[@time_offset] = 0
            context.start_using_reg(TMPR2)
            cntadd = @top_node.get_global_arena_end_address.value
            cntadd -= @cnt_offset * 8
            asm.with_retry do
              asm.push(EAX)
              asm.push(EDX)
#              asm.cpuid
              asm.rdtsc
              asm.sub(EAX, PROFR)
              asm.add(PROFR, EAX)
              asm.mov(TMPR2, cntadd)
              asm.add(INDIRECT_TMPR2, 1)
              asm.sub(TMPR2, 8)
              asm.shr(EAX, 5)
              asm.add(INDIRECT_TMPR2, EAX)
              asm.pop(EDX)
              asm.pop(EAX)
            end
            context.end_using_reg(TMPR2)
          end

          @body.compile(context)
        end
      end

      class ClassValueNode<BaseNode
        include HaveChildlenMixin

        def initialize(parent, define)
          super(parent)
          @define = define
        end

        def traverse_childlen
          yield @define
          yield @body
        end
        
        attr_accessor :define

        def collect_candidate_type(context)
          dmylit = LiteralNode.new(self, nil)
          arg = [dmylit, dmylit, @define]
          sig = []
          cursig = context.to_signature
          arg.each do |ele|
            ele.decide_type_once(cursig)
            sig.push ele.type
          end
          type = RubyType::BaseType.from_ruby_class(@define.klassclass)
          sig[2] = type
          context = @define.collect_candidate_type(context, arg, sig)

          @body.collect_candidate_type(context)
        end

        def compile(context)
#          raise "Can't compile"
          context = super(context)
          context = @define.compile(context)
          @body.compile(context)
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

      # yield(invokeblock)
      class YieldNode<BaseNode
        include NodeUtil
        include SendUtil

        def initialize(parent)
          super(parent)
          @name = "block yield"
          @frame_info = search_frame_info_without_inline
          @depth = 0
          @block_nodes = []
        end

        attr :name
        attr :frame_info
        attr_accessor :depth
        attr :block_nodes

        def collect_info(context)
          context.yield_node.last.push @parent
          context
        end

        def collect_candidate_type(context)
          context
        end

        def calling_convention(context)
          if @block_nodes[0].is_a?(BlockTopInlineNode) then
            :ytl_inline
          else
            :ytl
          end
        end

        def method_top_node(ctop, slf)
          nil
        end

        def compile(context)
          context = super(context)
          asm = context.assembler
          prevenv = @frame_info.offset_arg(0, BPR)
          prevenv2 = @frame_info.offset_arg(0, TMPR2)
          # offset of self is common, so it no nessery traverse prev frame
          # for @frame_info.
          slfarg = @frame_info.offset_arg(2, PTMPR)
          asm.with_retry do
            asm.mov(PTMPR, prevenv)
          end

          @depth.times do
            asm.with_retry do
              asm.mov(PTMPR, prevenv)
            end
          end
          
          asm.with_retry do
            asm.mov(PTMPR, slfarg)
          end
          context.set_reg_content(PTMPR, :self_of_block)
          context.ret_reg2 = PTMPR

          if @depth == 0 or
              @frame_info.parent.is_a?(BlockTopInlineNode) then
            context.ret_reg = @frame_info.offset_arg(1, BPR)
          else
            context.start_using_reg(TMPR2)
            asm.with_retry do
              asm.mov(TMPR2, prevenv)
            end
            (@depth - 1).times do
              asm.with_retry do
                asm.mov(TMPR2, prevenv2)
              end
            end
            asm.with_retry do
              asm.mov(TMPR2, @frame_info.offset_arg(1, TMPR2))
            end
            context.ret_reg = TMPR2
          end
            
          context.ret_node = self
          context.set_reg_content(context.ret_reg, self)
          context
        end
      end

      # Use when you wish call block without calling method with block
      class DirectBlockNode<BaseNode
        include NodeUtil

        include SendUtil

        def initialize(parent, blk)
          super(parent)
          @name = "direct call block"
          @block = blk
          @frame_info = search_frame_info
        end

        attr :name
        attr :frame_info

        def collect_info(context)
          context
        end

        def collect_candidate_type(context)
          context
        end

        def calling_convention(context)
          :ytl
        end

        def method_top_node(ctop, slf)
          @block
        end

        def compile(context)
          context = super(context)
          asm = context.assembler
          slfarg = OpIndirect.new(TMPR2, AsmType::MACHINE_WORD.size * 3)
          asm.with_retry do
            asm.mov(PTMPR, slfarg)
          end
          context.ret_reg = @block.code_space.var_base_address
          context.ret_reg2 = PTMPR
          context
        end
      end

      class CApiCommonNode<BaseNode
        include NodeUtil
        include SendUtil

        def initialize(parent, name, atype, rtype = :VALUE)
          super(parent)
          @name = name
          @frame_info = search_frame_info
          @arg_type = atype
          @ret_type = rtype
        end

        attr :name
        attr :frame_info
        attr :arg_type
        attr :ret_type

        def collect_candidate_type(context)
          context
        end

        def method_top_node(ctop, slf)
          nil
        end

        def compile(context)
          context = super(context)
          addr = lambda { 
            a = address_of(@name) 
            $symbol_table[a] = @name
            a
          }
          context.ret_reg = OpVarMemAddress.new(addr)
          context.ret_node = self
          context.set_reg_content(context.ret_reg, self)
          context
        end
      end

      # C API (fix arguments)
      class FixArgCApiNode<CApiCommonNode
        def calling_convention(context)
          :c_fixarg_raw
        end
      end

      # C API (variable arguments)
      class VarArgCApiNode<CApiCommonNode
        def calling_convention(context)
          :c_vararg_raw
        end
      end

      # Method name
      class MethodSelectNode<BaseNode
        include SendNodeCodeGen
        include NodeUtil

        def initialize(parent, name)
          super(parent)
          @name = name
          @calling_convention = :unkown
          @reciever = nil
          @send_node = nil
          @ruby_reciever = nil
          @inline_node = nil
          @frame_info = search_frame_info_without_inline
        end

        def set_reciever(sendnode)
          @send_node = sendnode
          if sendnode.is_fcall or sendnode.is_vcall then
            @reciever = @parent.class_top
            if @reciever == @parent.search_top and 
                !@reciever.is_a?(TopTopNode) then
              @reciever = @reciever.make_klassclass_node
            end
          else
            @reciever = sendnode.arguments[2]
          end
        end
        
        attr :name
        attr :calling_convention
        attr_accessor :reciever
        attr :inline_node

        def collect_candidate_type(context)
          context
        end

        def method_top_node(ctop, slf)
          if slf then
            ctop.search_method_with_super(@name, slf.ruby_type_raw)[0]
          else
            ctop.search_method_with_super(@name)[0]
          end
        end

        def skip_trace(body)
          while body.is_a?(TraceNode)
            body = body.body
          end

          body
        end

        def is_getter(body)
          body = skip_trace(body)
          if !body.is_a?(SetResultNode) then
            return false
          end

          val = skip_trace(body.value_node)
          if !val.is_a?(CRubyInstanceVarRefNode) then
            return false
          end
          
          body = body.body
          body = skip_trace(body)
          if !body.is_a?(MethodEndNode) then
            return false
          end
          
          val
        end

        def is_setter(body)
          body = skip_trace(body)
          res = body
          if !body.is_a?(CRubyInstanceVarAssignNode) then
            return false
          end
          
          val = skip_trace(body.val)
          if !val.is_a?(MultiplexNode) then
            return false
          end
          
          val = skip_trace(val.node)
          if !val.is_a?(LocalVarRefNode) or val.is_a?(SelfRefNode) then
            return false
          end
          
          body = body.body
          body = skip_trace(body)
          if !body.is_a?(SetResultNode) then
            return false
          end
          
          body = body.body
          body = skip_trace(body)
          if !body.is_a?(MethodEndNode) then
            return false
          end
          
          res
        end

        def calling_convention(context)
          if @send_node.is_fcall or @send_node.is_vcall then
            mtop = @reciever.search_method_with_super(@name)[0]
            if mtop then
              @calling_convention = :ytl
            else
              # reciever = Object
              recobj = @reciever.klass_object
              if recobj.is_a?(ClassClassWrapper) then
                recobj = recobj.value
              end
              if recobj and !recobj.is_a?(Class) then
                # recobj is Module
                recobj = Object
              end
              if recobj then
                addr = recobj.method_address_of(@name)
                $symbol_table[addr] = @name
                if addr then
                  mth = recobj.instance_method(@name)
                  if variable_argument?(mth.parameters) then
                    @calling_convention = :c_vararg
                  else
                    @calling_convention = :c_fixarg
                  end
                else
                  p parent.debug_info
                  raise "Unkown method - #{recobj}##{@name}"
                  @calling_convention = :c
                end
              else
                raise "foo"
              end
            end
          else
            sig = context.to_signature
=begin
            p @name
            p @parent.debug_info
            p context.to_signature
            p sig
            p @parent.arguments[2].class
=end

            if @reciever.type_list(sig).flatten.uniq.size != 0 then
              @reciever.type = nil
            end
            rtype = @reciever.decide_type_once(sig)
            rklass = rtype.ruby_type_raw

            knode = ClassTopNode.get_class_top_node(rklass)
            if knode and 
                (mtop = knode.search_method_with_super(@name)[0]) then
              @calling_convention = :ytl

              # Check getter/setter
              body = mtop.body.body
              # skip line no
              body = body.body if context.options[:profile_mode]
              # skip two trace node
              body = body.body.body
              if @inline_node = is_getter(body) then
                @calling_convention = :getter
              elsif @inline_node = is_setter(body) then
                @calling_convention = :setter
              end
              @ruby_reciever = rklass
            else
              slfval = @reciever.get_constant_value
              mth = nil
              if slfval then
                begin
                  # search normal method
                  mth = slfval[0].class.instance_method(@name)
                  @ruby_reciever = slfval[0].class
                rescue NameError
                  begin
                    # search sigleton method
                    mth = slfval[0].method(@name)
                    @ruby_reciever = ClassClassWrapper.instance(slfval[0])
                  rescue NameError
                  end
                end
              end
              if slfval == nil or mth == nil then
                if rklass.is_a?(ClassClassWrapper) then
                  rklass = rklass.value
                end
                begin
                  mth = rklass.instance_method(@name)
                  @ruby_reciever = rtype.ruby_type_raw
                rescue NameError
=begin
                  p @parent.debug_info
                  p sig
                  p @name
                  p @reciever.class
                  p @reciever.instance_eval {@type_list }
                  p @reciever.type_list(sig)
                  mc = @reciever.get_send_method_node(context.to_signature)[0]
                  iv = mc.end_nodes[0].parent.value_node
                  p iv.instance_eval {@name}
                  p iv.instance_eval {@type_list}
=end
                  tlist = @reciever.type_list(sig).flatten
                  if tlist.all? {|e| 
                      eklass = e.ruby_type_raw
                      knode = ClassTopNode.get_class_top_node(eklass)
                      knode and  knode.search_method_with_super(@name)[0]
                    } then
                    @calling_convention = :ytl

                  elsif tlist.all? {|e|
                      begin
                        mth = rklass.instance_method(@name)
                        variable_argument?(mth.parameters)
                      rescue NameError
                        false
                      end
                    } then
                    @calling_convention = :c_vararg
                  
                  elsif tlist.all? {|e|
                      begin
                        mth = rklass.instance_method(@name)
                        !variable_argument?(mth.parameters)
                      rescue NameError
                        false
                      end
                    } then
                    @calling_convention = :c_fixarg
                    
                  else
                    @calling_convention = :mixed
                  end

                  p sig
                  p @reciever.instance_eval {@type_list}
                  p @name
                  p @parent.debug_info
                  p @calling_convention
                  return @calling_convention
                end
              end

              if variable_argument?(mth.parameters) then
                @calling_convention = :c_vararg
              else
                @calling_convention = :c_fixarg
              end
            end
          end

          @calling_convention
        end

        def compile(context)
          context = super(context)
          if @send_node.is_fcall or @send_node.is_vcall then
            slfop = @frame_info.offset_arg(2, BPR)
            asm = context.assembler
            asm.with_retry do
              asm.mov(PTMPR, slfop)
            end
            context.set_reg_content(PTMPR, :callee_reciever)
            context.ret_reg2 = PTMPR
            mtop = @reciever.search_method_with_super(@name)[0]
            if mtop then
              sig = @parent.signature(context)
              cs = mtop.find_cs_by_signature(sig)
              if cs then
                context.ret_reg = cs.var_base_address
              else
                # Maybe not reached program
                context.ret_reg = 0
              end
            else
              recobj = @reciever.klass_object
              if recobj.is_a?(ClassClassWrapper) then
                recobj = recobj.value
              end
              if recobj and !recobj.is_a?(Class) then
                # recobj is Module
                recobj = Object
              end
              if recobj then
                addr = lambda {
                  a = recobj.method_address_of(@name)
                  $symbol_table[a] = @name
                  a
                }
                if addr.call then
                  context.ret_reg = OpVarMemAddress.new(addr)
                  context.code_space.refer_operands.push context.ret_reg 
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
            rnode = context.ret_node
            rtype = rnode.decide_type_once(context.to_signature)
            do_dyna = rtype.is_a?(RubyType::DefaultType0)
            if @calling_convention != :ytl then
              context = rtype.gen_boxing(context)
              rtype = rtype.to_box
            elsif !rtype.boxed then
              context = rtype.gen_unboxing(context)
            end
            recval = context.ret_reg
            rrtype = rtype.ruby_type_raw
            knode = ClassTopNode.get_class_top_node(rrtype)
            mtop = nil

            if do_dyna then
              # Can't type inference. Dynamic method search
              mnval = @name.address
              addr = lambda {
                a = address_of("rb_obj_class")
                $symbol_table[a] = "rb_obj_class"
                a
              }
              objclass = OpVarMemAddress.new(addr)
              addr = lambda {
                a = address_of("ytl_method_address_of_raw")
                $symbol_table[a] = "ytl_method_address_of_raw"
                a
              }
              addrof = OpVarMemAddress.new(addr)

              context.start_using_reg(TMPR2)
              context.start_arg_reg
              
              asm = context.assembler
              asm.with_retry do
                asm.push(recval)
                asm.mov(FUNC_ARG[0], recval)
                asm.call_with_arg(objclass, 1)
                asm.mov(FUNC_ARG[0], RETR)
                asm.mov(FUNC_ARG[1], mnval)
              end
              context.set_reg_content(FUNC_ARG[0], true)
              context.set_reg_content(FUNC_ARG[1], true)
              context = gen_save_thepr(context)
              asm.with_retry do
                asm.call_with_arg(addrof, 2)
                asm.mov(TMPR2, RETR)
                asm.pop(PTMPR)
              end
              context.set_reg_content(PTMPR, true)
              context.set_reg_content(FUNC_ARG_YTL[0].dst_opecode, true)
              context.set_reg_content(FUNC_ARG_YTL[1].dst_opecode, self)
              context.ret_reg2 = PTMPR
              
              context.end_arg_reg
              
              context.ret_node = self
              context.set_reg_content(RETR, :method_address)
              context.set_reg_content(TMPR2, RETR)
              context.set_reg_content(PTMPR, @reciever)
              context.ret_reg = TMPR2

            elsif knode and
                mtop = knode.search_method_with_super(@name)[0] then
              asm = context.assembler
              if !rtype.boxed and rtype.ruby_type == Float then
                if recval != XMM0 then
                  asm.with_retry do
                    asm.mov(XMM0, recval)
                  end
                end
                context.set_reg_content(XMM0, true)
                context.ret_reg2 = XMM0
              else
                asm.with_retry do
                  asm.mov(PTMPR, recval)
                end
                context.set_reg_content(PTMPR, @reciever)
                context.ret_reg2 = PTMPR
              end

              sig = @parent.signature(context)
              cs = mtop.find_cs_by_signature(sig)
              if cs == nil then
                sig[0] = context.to_signature[1]
                cs = mtop.find_cs_by_signature(sig)
              end
              context.ret_reg = cs.var_base_address
            else
              # regident type 

              asm = context.assembler
              if !rtype.boxed and rtype.ruby_type == Float then
                if recval != XMM0 then
                  asm.with_retry do
                    asm.mov(XMM0, recval)
                  end
                end
                context.ret_reg2 = XMM0
              else
                asm.with_retry do
                  asm.mov(PTMPR, recval)
                end
                context.set_reg_content(PTMPR, context.ret_node)
                context.set_reg_content(TMPR2, @reciever)
                context.ret_reg2 = PTMPR
              end

              addr = lambda {
                rrec = @ruby_reciever
                if rrec.is_a?(ClassClassWrapper) then
                  rrec = rrec.value
                end
                if rrec.class == Module then
                  a = rrec.send(:method_address_of, @name)
                  $symbol_table[a] = @name
                  a
                elsif rrec then
                  a = rrec.method_address_of(@name)
                  $symbol_table[a] = @name
                  a
                else
                  4
                end
              }
              if addr.call then
                context.ret_reg = OpVarMemAddress.new(addr)
                context.code_space.refer_operands.push context.ret_reg 
                context.ret_node = self
              else
                raise "Unkown method - #{@ruby_reciever}##{@name}"
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

        def set_current_frame_info
          frame_node = search_frame_info
          @frame_info = frame_node
          @depth.times do |i|
            frame_node = frame_node.previous_frame
          end
          @current_frame_info = frame_node
        end

        def initialize(parent, offset, depth)
          super(parent)
          @offset = offset
          @depth = depth

          cfi = set_current_frame_info
          roff = cfi.real_offset(offset)
          @var_node = cfi.frame_layout[roff]
          if @depth > 0 then
            @var_node.export_block = true
          end
        end
        
        attr :offset
        attr :depth
        attr :frame_info
        attr :current_frame_info
      end

      class LocalVarRefNode<LocalVarRefCommonNode
        def initialize(parent, offset, depth)
          super
          @var_type_info = nil
        end

        def collect_info(context)
          vti = nil
          if context.modified_local_var.last[-@depth - 1] then
            vti = context.modified_local_var.last[-@depth - 1][@offset]
          end

          if vti then
            if depth == 0 then
              @var_type_info = vti.map {|e| e.dup }
            else
              @var_type_info = vti
            end
          else
            raise "maybe bug"
            roff = @current_frame_info.real_offset(@offset)
            @var_type_info = [@current_frame_info.frame_layout[roff]]
          end

          context
        end

        def collect_candidate_type(context)
          cursig = context.to_signature
          @type = nil
          @var_type_info.reverse.each do |topnode, node|
            varsig = context.to_signature(topnode)
            same_type(self, node, cursig, varsig, context)
            node.set_escape_node(:not_export)
            # same_type(node, self, varsig, cursig, context)
          end
          context
        end

        def compile(context)
          context = super(context)
          context = gen_pursue_parent_function(context, @depth)
          base = context.ret_reg
          offarg = @current_frame_info.offset_arg(@offset, base)

          asm = context.assembler
          @type = nil
          rtype = decide_type_once(context.to_signature)
          if !rtype.boxed and rtype.ruby_type == Float then
            if offarg.is_a?(OpRegXMM) then
              context.ret_reg = offarg
            else
              asm.with_retry do
                asm.mov(XMM0, offarg)
              end
              context.ret_reg = XMM0
            end
          else
            asm.with_retry do
              asm.mov(TMPR, offarg)
            end
            context.ret_reg = TMPR
          end

          if base == TMPR2 then
            context.end_using_reg(TMPR2)
          end

          context.ret_node = self
          context
        end
      end

      class SelfRefNode<LocalVarRefNode
        def set_current_frame_info
          @frame_info = search_frame_info_without_inline
          @current_frame_info = @frame_info
        end

        def initialize(parent)
          super(parent, 2, 0)
          @classtop = search_class_top
          @topnode = search_top
        end

        def compile_main(context)
          dest = @current_frame_info.offset_arg(@offset, BPR)
          context.ret_node = self
          context.ret_reg = dest
          context
        end

        def collect_candidate_type(context)
          if @topnode.is_a?(ClassTopNode) then
            tt = RubyType::BaseType.from_ruby_class(@classtop.klass_object)
            cursig = context.to_signature
            # size of @var_type_info is always 1.because you can't assign self
            topnode, node = @var_type_info[0]

            vsig = context.to_signature(topnode)
            vtype = node.decide_type_once(vsig)
            node.set_escape_node(:not_export)
            @is_escape = node.is_escape
            same_type(self, node, cursig, vsig, context)
            if vtype.boxed != tt.boxed then
              if vtype.boxed then
                tt= tt.to_box
              else
                tt = tt.to_unbox
              end
            end
            add_type(cursig, tt)
            context
          else
            super(context)
          end
        end

        def compile(context)
#          context = super(context)
          compile_main(context)
        end
      end

      class LocalAssignNode<LocalVarRefCommonNode
        include HaveChildlenMixin
        def initialize(parent, offset, depth, val)
          super(parent, offset, depth)
          val.parent = self
          @val = val
          @var_from = nil
          @var_type_info = nil
          @referrers = []
          @dest = nil
        end

        attr :dest

        def add_referrer(ref)
          if @referrers and ref.id[0..-2] == id[0..-2] then
            @referrers.push.ref
            @referrers = @referrers..sort_by {|a| a.id.last}.uniq
          else
            @referrers = nil
          end
        end

        def traverse_childlen
          yield @val
          yield @body
        end

        def collect_info(context)
          context = @val.collect_info(context)
          top = @frame_info
          @depth.times do |i|
            top = top.previous_frame
          end
          @var_from = top.parent

          nodepare = nil
          if @depth > 0 then 
            nodepare = context.modified_local_var.last[-@depth - 1]
          end
          if nodepare then
            nodepare = nodepare[@offset]
          end
          if nodepare then
            nodepare.push [@var_from, self]
          else
            nodepare = [[@var_from, self]]
          end
            
          context.modified_local_var.last[-@depth - 1][@offset] = nodepare
          @var_type_info = nodepare

          @body.collect_info(context)
        end
          
        def collect_candidate_type(context)
          context = @val.collect_candidate_type(context)
          cursig = context.to_signature
          varsig = context.to_signature(@var_from)
          @var_type_info.reverse.each do |topnode, node|
            if node != self then
              varsig2 = context.to_signature(topnode)
              same_type(self, node, cursig, varsig2, context)
            end
          end
          same_type(self, @val, varsig, cursig, context)
          same_type(@var_node, @val, varsig, cursig, context)
#          same_type(@val, self, cursig, varsig, context)

          @body.collect_candidate_type(context)
        end

        def compile(context)
          context = super(context)

          if @depth == 0 then
            @dest = @current_frame_info.offset_arg(@offset, BPR)
          else
            @dest = nil
          end

          context = @val.compile(context)

          cursig = context.to_signature
          varsig = context.to_signature(-@depth - 1)

          vartype = decide_type_once(varsig)
          valtype = @val.decide_type_once(cursig)

          asm = context.assembler
          # type conversion
          if vartype.ruby_type == Float and
              valtype.ruby_type == Fixnum then
            context = valtype.gen_unboxing(context)
            asm.with_retry do
              asm.mov(TMPR, context.ret_reg)
              asm.cvtsi2sd(XMM0, TMPR)
            end
            context.ret_reg = XMM0
            valtype = valtype.to_unbox
          end

          if vartype.boxed then
            context = valtype.gen_boxing(context)
          else
            context = valtype.gen_unboxing(context)
          end
          valr = context.ret_reg

          if !@dest then
            context = gen_pursue_parent_function(context, @depth)
            base = context.ret_reg
            @dest = @current_frame_info.offset_arg(@offset, base)
          end

          if @dest != valr then
            if valr.is_a?(OpRegistor) or 
                (@dest.is_a?(OpRegistor) and valr.is_a?(OpIndirect)) or
                (valr.is_a?(OpImmidiate) and !valr.is_a?(OpImmidiate64)) then
              asm.with_retry do
                asm.mov(@dest, valr)
              end
              
            elsif @dest.is_a?(OpRegXMM) then
              asm.with_retry do
                asm.mov(XMM0, valr)
                asm.mov(@dest, XMM0)
              end

            else
              asm.with_retry do
                asm.mov(TMPR, valr)
                asm.mov(@dest, TMPR)
              end
            end
          end

          tmpctx = context
          @depth.times { tmpctx = tmpctx.prev_context}
          tmpctx.set_reg_content(@dest, @val)

          context.ret_reg = TMPR
          if base == TMPR2 then
            context.end_using_reg(base)
          end

          @body.compile(context)
        end
      end

      # Instance Variable
      class InstanceVarRefCommonNode<VariableRefCommonNode
        include NodeUtil

        def initialize(parent, name, mnode)
          super(parent)
          @name = name
          @method_node = mnode
          mname = nil
          if @method_node then
            mname = @method_node.get_constant_value
          end
          @method_name = mname
          @class_top = search_class_top
        end
      end

      class InstanceVarRefNode<InstanceVarRefCommonNode
        def initialize(parent, name, mnode)
          super
          @var_type_info = nil
        end

        def collect_info(context)
          vti = context.modified_instance_var[@name]
          if vti == nil then
            vti = []
            context.modified_instance_var[@name] = vti
          end
          # Not dup so vti may update after.
          @var_type_info = vti 

          context
        end

        def collect_candidate_type(context)
          cursig = context.to_signature
          @var_type_info.each do |node, sigs|
            sigs.each do |sig|
              same_type(self, node, cursig, sig, context)
            end
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
        def initialize(parent, name, mnode, val)
          super(parent, name, mnode)
          val.parent = self
          @val = val
          @curpare = [self, []]
        end

        attr :val

        def traverse_childlen
          yield @val
          yield @body
        end

        def collect_info(context)
          context = @val.collect_info(context)
          if context.modified_instance_var[@name] == nil then
            context.modified_instance_var[@name] = []
          end
          context.modified_instance_var[@name].push @curpare
          @body.collect_info(context)
        end

        def collect_candidate_type(context)
          context = @val.collect_candidate_type(context)
          cursig = context.to_signature
          if !@curpare[1].include? cursig then
              @curpare[1].push cursig
          end
          same_type(self, @val, cursig, cursig, context)
#          same_type(@val, self, cursig, cursig, context)
          @val.type = nil
          rtype = @val.decide_type_once(cursig)
          rrtype = rtype.ruby_type
          if rrtype != Fixnum and rrtype != Float then
            slfnode = context.current_method_signature_node[-1][2]
            if slfnode.is_escape == :global_export then
              @val.set_escape_node(:global_export)
              context = @val.collect_candidate_type(context)
#              context.convergent = false
            else
              @val.set_escape_node_backward(:local_export)
            end
          end
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

      # Global Variable
      class GlobalVarRefNode<VariableRefCommonNode
        def self.instance(parent, name)
          case name.to_s
          when /^\$[^a-zA-Z_]/,
            /^\$_$/, /^\$FILENAME$/, /^\$DEBUG$/,  /^\$KCODE$/,
            /^\$stdin$/, /^\$stdout$/,  /^\$stderr$/
            GlobalVarSpecialRefNode.new(parent, name)
          else
            GlobalVarNormalRefNode.new(parent, name)
          end
        end

        def collect_info(context)
          context.modified_global_var[@name] ||= []
          @assign_nodes = context.modified_global_var[@name]
          context
        end
      end


      class GlobalVarNormalRefNode<GlobalVarRefNode
        include NodeUtil
        include TypeListWithoutSignature
        include UnboxedArrayUtil
        def initialize(parent, name)
          super(parent)
          @name = name
          @assign_nodes = nil
          @offset = nil
        end

        def collect_candidate_type(context)
          if @assign_nodes then
            @offset = @assign_nodes[0][0].offset
            sig = context.to_signature
            @assign_nodes.reverse.each do |an, asig|
              same_type(self, an, sig, asig, context)
            end
          end
          context
        end

        def compile(context)
          sig = context.to_signature
          asm = context.assembler
          context.start_using_reg(TMPR2)
          asm.with_retry do
            asm.mov(TMPR2, context.top_node.get_global_arena_end_address)
          end
          context.set_reg_content(TMPR2, :global_arena)
          context = gen_ref_element(context, nil, -@offset)
          context.end_using_reg(TMPR2)
          rtype = decide_type_once(sig)
          if rtype.ruby_type == Float and !rtype.boxed then
            asm.with_retry do
              asm.mov(XMM0, context.ret_reg)
            end
            context.ret_reg = XMM0
          else
            asm.with_retry do
              asm.mov(RETR, context.ret_reg)
            end
            context.ret_reg = RETR
          end
          context
        end
      end

      class GlobalVarSpecialRefNode<GlobalVarRefNode
        include NodeUtil
        include TypeListWithoutSignature
        include UnboxedArrayUtil
        include SendNodeCodeGen

        def initialize(parent, name)
          super(parent)
          @name = name
          @assign_nodes = nil
          @offset = nil
        end

        def collect_candidate_type(context)
          case @name
          when :$_
            tt = RubyType::BaseType.from_ruby_class(String)
          else
            tt = RubyType::BaseType.from_object(eval(@name.to_s))
          end
          sig = context.to_signature
          add_type(sig, tt)
          
          context
        end

        def compile(context)
          asm = context.assembler
          add = lambda { 
            a = address_of("rb_global_entry")
            $symbol_table[a] = "rb_global_entry"
            a
          }
          gentry = OpVarMemAddress.new(add)

          add = lambda { 
            a = address_of("rb_gvar_get")
            $symbol_table[a] = "rb_gvar_get"
            a
          }
          gget = OpVarMemAddress.new(add)
          wsize = AsmType::MACHINE_WORD.size
          symid = ((@name.__id__ << 1) / (5 * wsize))
          asm.with_retry do
            asm.mov(FUNC_ARG[0], symid)
          end
          context = gen_save_thepr(context)
          context = gen_call(context, gentry, 1)

          asm.with_retry do
            asm.mov(FUNC_ARG[0], RETR)
          end
          context = gen_save_thepr(context)
          context = gen_call(context, gget, 1)

          context.ret_reg = RETR
          context
        end
      end

      class GlobalVarAssignNode<VariableRefCommonNode
        include NodeUtil
        include HaveChildlenMixin
        include TypeListWithoutSignature
        include UnboxedArrayUtil
        def initialize(parent, name, value)
          super(parent)
          @name = name
          @value = value
          @assign_nodes = nil
          @offset = nil
          @assign_no = nil
        end

        attr :offset

        def collect_info(context)
          context = @value.collect_info(context)
          context.modified_global_var[@name] ||= []
          @assign_nodes = context.modified_global_var[@name]
          asize = @assign_nodes.size
          if asize == 0 then
            @offset = context.modified_global_var.keys.size - 1
          end
          @assign_no  = asize
          @assign_nodes.push [self, nil]
          @body.collect_info(context)
        end

        def collect_candidate_type(context)
          sig = context.to_signature
          @assign_nodes[@assign_no][1] = sig
          context = @value.collect_candidate_type(context)
          same_type(self, @value, sig, sig, context)
          if @offset == nil then
            @offset = @assign_nodes[0][0].offset
          end
          @body.collect_candidate_type(context)
        end

        def compile(context)
          sig = context.to_signature
          asm = context.assembler
          context.start_using_reg(TMPR2)
          asm.with_retry do
            asm.mov(TMPR2, context.top_node.get_global_arena_end_address)
          end
          context.set_reg_content(TMPR2, :global_arena)
          contet = gen_set_element(context, nil, -@offset, @value)
          context.end_using_reg(TMPR2)
          @body.compile(context)
        end
      end
      
      # Constant
      class ConstantRefNode<VariableRefCommonNode
        include NodeUtil
        include TypeListWithoutSignature
        
        def initialize(parent, klass, name)
          super(parent)
          @name = name
          rklass = nil
          case klass
          when LiteralNode, ConstantRefNode
            rklass = klass.get_constant_value[0]
            klass = ClassTopNode.get_class_top_node(rklass)

          when ClassTopNode
            rklass = klass.get_constant_value[0]
            
          else
            klass = search_class_top
          end

          @class_top = klass # .search_class_top
          @rklass = rklass
          @value_node = nil
          set_value_node
        end

        def set_value_node
          klass = @class_top
          rklass = @rklass
          clsnode = nil
          if klass then
            @value_node, clsnode = klass.search_constant_with_super(@name)
          end
          if clsnode == nil and rklass then
            begin
              @value_node = LiteralNode.new(self, rklass.const_get(@name))
            rescue
            end
          end
        end

        attr :value_node

        def collect_candidate_type(context)
          if @value_node.is_a?(ClassTopNode) or 
              @value_node.is_a?(LiteralNode) then
            if @value_node.type then
              add_type(context.to_signature, @value_node.type)
            else
              # this inference not complete so repeat type inference
              context.convergent = false
            end
          else
            cursig = context.to_signature
            same_type(self, @value_node, cursig, cursig, context)
          end

          context
        end

        def collect_info(context)
          if @value_node == nil then
            set_value_node
          end
          super
        end

        def compile(context)
          case @value_node
          when ClassTopNode
            obj = @value_node.klass_object
            objadd = lambda { obj.address }
            context.ret_reg  = OpVarImmidiateAddress.new(objadd)

          else
            context = @value_node.compile_get_constant(context)
          end
          
          context.ret_node = self
          context 
        end

        def get_constant_value
          @value_node.get_constant_value
        end
      end

      class ConstantAssignNode<VariableRefCommonNode
        include NodeUtil
        include HaveChildlenMixin
        include TypeListWithoutSignature
        
        def initialize(parent, klass, name, value)
          super(parent)
          @name = name
          @class_top = klass # .search_class_top
          
          pvalue = nil
          @value = value
          @value_node = value
          if !value.is_a?(LiteralNode) then
            @value_node = self
          end

          if klass.is_a?(ClassTopNode) then
            klass.constant_tab[@name] = @value_node
          else
            pp klass.class
            raise "Not Implemented yet for set constant for dynamic class"
          end
          @constant_area = nil
        end

        def traverse_childlen
          yield @value
          yield @body
        end

        def collect_candidate_type(context)
          sig = context.to_signature
          context = @value.collect_candidate_type(context)
          same_type(self, @value, sig, sig, context)
          @body.collect_candidate_type(context)
        end
        
#        def type
#          @value.type
#        end

        def compile_get_constant(context)
          asm = context.assembler
          rtype = decide_type_once(context.to_signature)
          retr = RETR
          if rtype.ruby_type == Float and !rtype.boxed then
            retr = XMM0
          end
          asm.with_retry do
            asm.mov(TMPR, @constant_area)
            asm.mov(retr, INDIRECT_TMPR)
          end
          context.ret_reg = retr
          context.ret_node = self
          context
        end

        def compile(context)
          if !@value.is_a?(LiteralNode) then
            asm = context.assembler
            valproc = lambda { 4 }
            varnilval = OpVarMemAddress.new(valproc)
            @constant_area = asm.add_value_entry_no_cache(varnilval)
            @constant_area = @constant_area.to_immidiate
            context = @value.compile(context)
            rtype = decide_type_once(context.to_signature)
            tmpr = TMPR
            if rtype.ruby_type == Float and !rtype.boxed then
              tmpr = XMM0
            end
            
            asm.with_retry do
              asm.push(TMPR2)
              asm.mov(tmpr, context.ret_reg)
              asm.mov(TMPR2, @constant_area)
              asm.mov(INDIRECT_TMPR2, tmpr)
              asm.pop(TMPR2)
            end
          end

          @body.compile(context)
        end
      end

      # Reference Register
      class RefRegister
      end
    end
  end
end
