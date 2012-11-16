module YTLJit
  module VM
    # Expression of VM is a set of Nodes
    module Node
      # Opt_flag operation
      module OptFlagOp
        def is_args_splat
          (@opt_flag & (1 << 1)) != 0
        end

        def is_args_blockarg
          (@opt_flag & (1 << 2)) != 0
        end

        def is_fcall
          (@opt_flag & (1 << 3)) != 0
        end

        def is_vcall
          (@opt_flag & (1 << 4)) != 0
        end

        def is_tailcall
          (@opt_flag & (1 << 5)) != 0
        end

        def is_tailrecursion
          (@opt_flag & (1 << 6)) != 0
        end

        def is_super
          (@opt_flag & (1 << 7)) != 0
        end

        def is_opt_send
          (@opt_flag & (1 << 8)) != 0
        end
      end

      # Send methodes
      class SendNode<BaseNode
        include HaveChildlenMixin
        include OptFlagOp
        include SendNodeCodeGen
        include NodeUtil
        include SendUtil

        @@current_node = nil
        @@special_node_tab = {}
        @@macro_tab = {}
        @@user_defined_method_tab = {}
        
        def self.node
          @@current_node
        end

        def self.get_macro_tab
          @@macro_tab
        end

        def self.get_user_defined_method_tab
          @@user_defined_method_tab
        end

        def self.add_special_send_node(name)
          oldcls = @@special_node_tab[name]
          if oldcls == nil or self < oldcls then
            @@special_node_tab[name] = self

          else
            raise "Illigal SendNode #{self} #{name}"
          end
        end

        def self.get_special_send_node(name)
          cls = @@special_node_tab[name]
          if cls then
            cls
          else
            SendNode
          end
        end

        def self.macro_expand(context, func, arguments, op_flag, seqno)
          if @@macro_tab[func.name] and 
              (op_flag & (0b11 << 3)) != 0 then
            cclsnode = context.current_class_node
            if context.current_method_name == nil then
              cclsnode = cclsnode.make_klassclass_node
            end

            cclsnode.klass_object.ancestors.each do |ccls|
              cnode = ClassTopNode.get_class_top_node(ccls)
              cobj = nil
              if cnode then
                cobj = cnode.klass_object
              end

              if @@user_defined_method_tab[func.name] and
                  @@user_defined_method_tab[func.name].include?(cobj) then
                return nil
              end

              mproc = @@macro_tab[func.name][cobj]
              if mproc then
                args = []
                arguments[3..-1].each do |ele|
                  argruby = ele.to_ruby(ToRubyContext.new).ret_code.last
                  args.push eval(argruby)
                end

                # define used methods in macro
                @@macro_tab.each do |name, val|
                  val.each do |rec, proc|
                    if rec.is_a?(Module) then
                      name1 = ("ytl__eval_" + name.to_s).to_sym
                      if proc.is_a?(Proc)
                        rec.class_eval {define_method(name1, &proc)}
                      end
                    end
                  end
                end

                # call eval included method
                return mproc.call(*args)
              end
            end
          end

          nil
        end

        def self.make_send_node(parent, func, arguments, op_flag, seqno)
          spcl = @@special_node_tab[func.name]
          newobj = nil
          if spcl then
            newobj = spcl.new(parent, func, arguments, op_flag, seqno)
          else
            newobj = self.new(parent, func, arguments, op_flag, seqno)
          end
          func.parent = newobj
          arguments.each do |ele|
            ele.parent = newobj
          end

          newobj
        end

        def initialize(parent, func, arguments, op_flag, seqno)
          super(parent)
          @func = func
          @arguments = arguments
          @opt_flag = op_flag
          @seq_no = seqno
          @next_node = @@current_node
          @@current_node = self

          @class_top = search_class_top
          @frame_info = search_frame_info

          @modified_instance_var = nil
          @modified_local_var = [{}]

          @result_cache = nil
          @method_signature = []
          @yield_signature_cache = {}

          @current_exception_table = nil
        end

        attr_accessor :func
        attr_accessor :arguments
        attr          :opt_flag
        attr          :next_node
        attr          :class_top
        attr          :frame_info
        attr          :modified_local_var
        attr          :modified_instance_var
        attr_accessor :result_cache
        attr          :seq_no
        attr          :yield_signature_cache

        attr_accessor :current_exception_table

        def traverse_node(&blk)
          @arguments.each_with_index do |arg, i|
            if arg.is_a?(SendNode) then
              arg.traverse_node(&blk)
            else
              yield(arg, @arguments, i)
            end
          end
        end

        def traverse_childlen
          @arguments.each do |arg|
            yield arg
          end
          yield @func
          yield @body
        end

        def get_send_method_node(cursig)
          mt = nil
          if @arguments[2].type_list(cursig) != [[], []] then
            @arguments[2].type = nil
          end
          slf = nil
          if is_fcall or is_vcall then
            slf =  @arguments[2].decide_type_once(cursig)
            mt = @func.method_top_node(@class_top, nil)
          else
            slf = @arguments[2].decide_type_once(cursig)
            if slf.instance_of?(RubyType::DefaultType0) then
              # Chaos
              #p debug_info
              #p cursig
              #p @arguments[2].instance_eval { @type_list }
              #            raise "chaos"
            end
            
            mt = @func.method_top_node(@class_top, slf)
          end

          [mt, slf]
        end

        def collect_candidate_type_regident(context, slf)
          context
        end

        # This is for reduce method call whose all arguments is constant.
        # But all methods can't apply because the method may have side
        # effect.
        def fill_result_cache(context)
          context
        end

        def collect_info(context)
          @arguments.each do |arg|
            context = arg.collect_info(context)
          end
          context = @func.collect_info(context)
          if is_fcall or is_vcall then
            # Call method of same class
            mt = @class_top.get_method_tab[@func.name]
            if mt then
              miv = mt.modified_instance_var
              if miv then
                miv.each do |vname, vall|
                  context.modified_instance_var[vname] = vall
                end
              end
            end
          end

          @modified_local_var    = context.modified_local_var.last
          @modified_instance_var = context.modified_instance_var

          context = fill_result_cache(context)

          @body.collect_info(context)
        end

        def search_signature(cursig)
          @method_signature.each do |tabent|
            if cursig == tabent[0] then
              return tabent
            end
          end
          nil
        end

        def check_signature_changed(context, signat, metsigent, cursig)
          if metsigent then
            if metsigent[1][1] != signat[1] then
              # Why not push, because it excepted type inference about
              # this signature after. So reduce search loop.
              @method_signature.unshift [cursig, signat]
              context.convergent = false
              signat[1].ruby_type < metsigent[1][1].ruby_type
            else
              false
            end

          else
            @method_signature.unshift [cursig, signat]
            false
          end
        end

        # inherit self/block from caller node
        def inherit_from_callee(context, cursig, prevsig, signat, args, nest)
          if context.is_a?(TypeInferenceContext) then
            (0..2).each do |n|
              args[n] = context.current_method_signature_node[-2 - nest][n]
            end
          end
          (0..2).each do |n|
            signat[n] = prevsig[n]
          end

          if args[2].decide_type_once(cursig).ruby_type == Object then
            context.current_method_signature_node.reverse.each {|e0| 
              if e0[2].class == SendNewArenaNode then
                if args[2].type then
                  args[2] = e0[2]
                  signat[2] = args[2].type
                end
                break
              end
            }
          end
        end

        def collect_candidate_type_block(context, blknode, signat, mt, cursig)
          # traverse a nested block
          # mt and signat are set corresponding to the nest level of yield
          if @func.is_a?(YieldNode) and false then
            level = @depth
          else
            level = 0
          end
          nest = 0
          sn = nil
          while mt.yield_node.size == 0 and
              mt.send_nodes_with_block.size != 0
            sn = mt.send_nodes_with_block[0]
            mt, slf = sn.get_send_method_node(cursig)
            if mt == nil then
              return context
            end
            args = sn.arguments

            context.push_signature(args, mt)

            nest = nest + 1
            if mt.yield_node.size == 0 then
              break
            end
            ynode = mt.yield_node[0]
            yargs = ynode.arguments.dup
            (0..2).each do |n|
              cl = nest + level
              yargs[n] = context.current_method_signature_node[-1 - cl][n]
            end
            mt = args[1]
            context.push_signature(yargs, mt)
            nest = nest + 1
          end
          if sn then
            signat = sn.signature(context)
          end

          mt.yield_node.map do |ynode|
            if !ynode.func.block_nodes.include?(blknode) then
              ynode.func.block_nodes.push blknode
            end
            yargs = ynode.arguments.dup
            yargs[2.. -1].each do |arg|
              context = arg.collect_candidate_type(context)
            end
            ysignat = ynode.signature(context)

            # inherit self from caller node
            # notice: this region pushed callee signature_node
            cl =   nest + level
            prevsig = context.to_signature(-2 - cl)
            inherit_from_callee(context, cursig, prevsig, ysignat, yargs, cl)
#            ysignat[1] = signat[0]
            
            # collect candidate type of block and yield
            context = blknode.collect_candidate_type(context, yargs, ysignat)
            same_type(ynode, blknode, signat, ysignat, context)
            @yield_signature_cache[cursig] = ysignat
            
            # fill type cache(@type) of block node
            blknode.type = nil
            blknode.decide_type_once(ysignat)
          end

          nest.times do 
            context.pop_signature
          end
          
          context
        end

        def collect_candidate_type(context)
          cursig = context.to_signature

          # get saved original signature
          metsigent = search_signature(cursig)

          # prev env
          context = @arguments[0].collect_candidate_type(context)

          # block is after detect method
          blknode = @arguments[1]

          # other
          @arguments[2.. -1].each do |arg|
            context = arg.collect_candidate_type(context)
          end

          # function select
          context = @func.collect_candidate_type(context)

          signat = signature(context)
          ysig = @yield_signature_cache[cursig]
          if ysig then
            signat[1] = blknode.decide_type_once(ysig)
          end
          if @func.is_a?(YieldNode) then
            signat[1] = cursig[0]
          end
=begin
          if changed then
            @arguments.each do |arg|
              arg.type = nil
            end
            signat = signature(context)
          end
=end

          mt, slf = get_send_method_node(cursig)
          if mt then
=begin
            changed = check_signature_changed(context, signat, 
                                              metsigent, cursig)
            if changed then
              mt.type_list(metsigent[1])[1] = []
              mt.ti_reset
            end
=end
            extargs = extend_args(context, @arguments)
            context = mt.collect_candidate_type(context, extargs, signat)

            if blknode.is_a?(TopNode) then
              context.push_signature(extargs, mt)
              # Have block
              context = collect_candidate_type_block(context, blknode, 
                                                     signat, mt, cursig)
              context.pop_signature
              if signat[1] != blknode.type then
                signat[1] = blknode.type
                context = mt.collect_candidate_type(context, 
                                                    extargs, signat)
              end
            else
              context.push_signature(extargs, mt)
              context = blknode.collect_candidate_type(context)
              context.pop_signature
            end
            same_type(self, mt, cursig, signat, context)

          else
            context = collect_candidate_type_regident(context, slf)
          end

          if @func.is_a?(YieldNode) then
            add_type(cursig, cursig[1])
            @type = nil
            decide_type_once(cursig)
          end
          @body.collect_candidate_type(context)
        end

        def compile(context)
          context = super(context)

          @type = nil
          cursig = context.to_signature
          context.start_using_reg(TMPR2)
          context.start_using_reg(PTMPR)
          callconv = @func.calling_convention(context)
          
          case callconv
          when :c_vararg
            context = compile_c_vararg(context)
            
          when :c_fixarg
            context = compile_c_fixarg(context)

          when :c_fixarg_raw
            context = compile_c_fixarg_raw(context)

          when :ytl
            if is_args_splat then
              context = compile_ytl_ext_ary(context)
            else
              context = compile_ytl(context)
            end

          when :getter
            inode = @func.inline_node
            context = @arguments[2].compile(context)
            rectype = @arguments[2].decide_type_once(cursig)
            context = inode.compile_main_aux(context, context.ret_reg, rectype)

          when :setter
            inode = @func.inline_node
            context = @arguments[2].compile(context)
            rectype = @arguments[2].decide_type_once(cursig)
            context = inode.compile_main_aux(context, context.ret_reg, rectype, 
                                             @arguments[3], nil)

          when :ytl_inline
            context = compile_ytl_inline(context)

          when nil

          else
#            p @arguments[2].type_list(context.to_signature)
#            p @func.name
#            raise "Unsupported calling conversion #{callconv}"
          end
          
          decide_type_once(cursig)
          if !@type.boxed and 
              @type.ruby_type == Float then
            context.ret_reg = XMM0
          else
            context.ret_reg = RETR
          end
          context.ret_node = self
          context.end_using_reg(PTMPR)
          context.end_using_reg(TMPR2)
          
          context = @body.compile(context)
          context
        end

        def get_constant_value
          if @result_cache then
            [@result_cache]
          else
            nil
          end
        end
      end

      class SendCoreDefineMethodNode<SendNode
        add_special_send_node :"core#define_method"
        def initialize(parent, func, arguments, op_flag, seqno)
          super
          @new_method = arguments[5]
          if arguments[4].is_a?(LiteralNode) then
            fname = arguments[4].value
            @new_method.name = fname
            @class_top.get_method_tab[fname] = @new_method
            if @@macro_tab[fname] and 
                @@macro_tab[fname][:last] then
              # This function is macro
              proc = @@macro_tab[fname][:last]
              @@macro_tab[fname][:last] = nil
              @@macro_tab[fname][@class_top.klass_object] = proc
            end
          else
            raise "Not supported not literal method name"
          end
        end

        def traverse_childlen
          yield @body
          yield @new_method
        end

        def collect_info(context)
          context = @new_method.collect_info(context)
          @body.collect_info(context)
        end

        def collect_candidate_type(context)
          # type inference of @new method execute when "send" instruction.
          @body.collect_candidate_type(context)
          context
        end

        def compile(context)
          context = @body.compile(context)
          ocs = context.code_space
          # Allocate new code space in compiling @new_method
          context = @new_method.compile(context)
          context.set_code_space(ocs)

          context.ret_reg = 4   # nil
          context.ret_node = self

          context
        end
      end

      class SendCoreDefineSigletonMethodNode<SendNode
        add_special_send_node :"core#define_singleton_method"

        def initialize(parent, func, arguments, op_flag, seqno)
          super
          @new_method = arguments[5]
          if arguments[4].is_a?(LiteralNode) then
            fname = arguments[4].value
            @new_method.name = fname
            klassclass_node = @class_top.make_klassclass_node
            if @@macro_tab[fname] and 
                @@macro_tab[fname][:last] then
              proc = @@macro_tab[fname][:last]
              @@macro_tab[fname][:last] = nil
              @@macro_tab[fname][klassclass_node.klass_object] = proc
            end
          else
            raise "Not supported not literal method name"
          end
        end

        def traverse_childlen
          yield @arguments[3]
          yield @body
          yield @new_method
        end

        def collect_info(context)
          context = @arguments[3].collect_info(context)
          context = @new_method.collect_info(context)
          @body.collect_info(context)
        end

        def collect_candidate_type(context)
          # type inference of @new method execute when "send" instruction.
          context = @arguments[3].collect_candidate_type(context)
          @arguments[3].decide_type_once(context.to_signature)
          rrtype = ClassClassWrapper.instance(@arguments[3].type.ruby_type)
          clsnode = ClassTopNode.get_class_top_node(rrtype)
          clsnode.get_method_tab[@new_method.name] = @new_method

          @body.collect_candidate_type(context)
        end

        def compile(context)
          context = @body.compile(context)
          ocs = context.code_space
          # Allocate new code space in compiling @new_method
          context = @new_method.compile(context)
          context.set_code_space(ocs)

          context.ret_reg = 4   # nil
          context.ret_node = self

          context
        end
      end
      
      class SendEvalNode<SendNode
        add_special_send_node :eval
      end

      class SendUnpackNode<SendNode
        add_special_send_node :unpack

        def collect_candidate_type_regident(context, slf)
          if slf.ruby_type == String
            cursig = context.to_signature
            arytype = RubyType::BaseType.from_ruby_class(Array)
            add_type(cursig, arytype)

            fmt = @arguments[3].get_constant_value
            if fmt.is_a?(Array) and fmt[0].is_a?(String) then
              fmt = fmt[0]
            else
              fmt = nil
            end
            fmt.each_char do |ch|
              type = nil
              case ch
              when 'c', 'C', 's', 'S', 'i', 'I', 'l', 'L', 'n', 'N', 'v', 'V'
                type = RubyType::BaseType.from_ruby_class(Fixnum)

              when 'a', 'A', 'Z', 'b', 'B', 'h', 'H', 'm', 'M', 'u', 'U', 'w'
                type = RubyType::BaseType.from_ruby_class(String)
                
              when 'f', 'd', 'e', 'E', 'g', 'G'
                type = RubyType::BaseType.from_ruby_class(Float)

              end

              if type then
                tnode = TypedDummyNode.instance(cursig, type)
                add_element_node(arytype, cursig, tnode, nil, context)
              end
            end
          end

          context
        end
      end

      class SendIncludeCommonNode<SendNode
        def collect_info(context)
          slfnode = @arguments[2]
          modvalue = @arguments[3].value_node
          modnode = ClassTopNode.get_class_top_node(modvalue.get_constant_value[0])
          add_search_module(slfnode, modnode)
          super
        end

        def collect_candidate_type_regident(context, slf)
          slfnode = @arguments[2]
          rtype = slfnode.decide_type_once(context.to_signature)
          add_type(context.to_signature, rtype)

          context
        end

        def compile(context)
          @body.compile(context)
        end
      end

      class SendIncludeNode<SendIncludeCommonNode
        add_special_send_node :include

        def add_search_module(slfnode, modnode)
          clstop =  slfnode.search_class_top
          clstop.add_after_search_module(:parm, modnode)
        end
      end

      class SendExtendNode<SendIncludeCommonNode
        add_special_send_node :extend

        def add_search_module(slfnode, modnode)
          clsclstop =  slfnode.search_class_top.make_klassclass_node
          clsclstop.add_after_search_module(:parm, modnode)
        end
      end

      class SendAllocateNode<SendNode
        include UnboxedObjectUtil
        include SendSingletonClassUtil

        add_special_send_node :allocate
        
        def collect_candidate_type_regident(context, slf)
          slfnode = @arguments[2]
          cursig = context.to_signature
          if slf.ruby_type.is_a?(Class) then
            tt = get_singleton_class_object(@arguments[2])
            clt =  ClassTopNode.get_class_top_node(tt.ruby_type_raw)
            @type = nil
            if context.options[:compile_array_as_uboxed] and
                tt.ruby_type != Array and
                @is_escape and @is_escape != :global_export and
                (clt and  !clt.body.is_a?(DummyNode)) then
              tt = tt.to_unbox
            elsif type_list(cursig)[0].include?(tt.to_unbox) then
              type_list(cursig)[0] = []
            end

            # set element type
            parg = @parent.arguments
            if tt.ruby_type == Range then
              if @is_escape != :global_export then
                tt = tt.to_unbox
              end
              tt.args = parg[3..-1]
              add_element_node(tt, cursig, parg[3], [0], context)
              add_element_node(tt, cursig, parg[4], [1], context)
              
            elsif tt.ruby_type == Array then
              if context.options[:compile_array_as_uboxed] and 
                  @is_escape and @is_escape != :global_export then
                if @element_node_list.size > 1 and
                    @element_node_list[1..-1].all? {|e|
                    e[3] or e[2].class == BaseNode
                  } then
                  tt = tt.to_unbox
                elsif parg[3] and 
                    siz0 = parg[3].get_constant_value and 
                    (siz = siz0[0]) < 10 then
                  @element_node_list = []
                  dnode = LiteralNode.new(self, nil)
                  tt = tt.to_unbox
                  siz.times do |i|
                    add_element_node(tt, cursig, dnode, [i], context)
                  end
                end
              end
              if parg[4] then
                siz = parg[3].get_constant_value
                if siz and false then
                  # Here is buggy yet Fix me
                  siz[0].times do |i|
                    add_element_node(tt, cursig, parg[4], [i], context)
                  end
                else
                  add_element_node(tt, cursig, parg[4], nil, context)
                end
              end
            end

            add_type(cursig, tt)
          end
          context
        end

        def compile(context)
          rtype = decide_type_once(context.to_signature)
          rrtype = rtype.ruby_type
          if !rtype.boxed then
            clt =  ClassTopNode.get_class_top_node(rrtype)
            mivl = clt.end_nodes[0].modified_instance_var.keys
            compile_object_unboxed(context, mivl.size)
          else
            super
          end
        end
      end

      class SendInitializeNode<SendNode
        add_special_send_node :initialize

        def compile(context)
          context.start_using_reg(TMPR2)
          context.start_using_reg(PTMPR)
          callconv = @func.calling_convention(context)

          case callconv
          when :c_vararg
            context = compile_c_vararg(context)
            
          when :c_fixarg
            context = compile_c_fixarg(context)

          when :ytl
            context = compile_ytl(context)

          else
            raise "Unsupported calling conversion #{callconv}"
          end

          asm = context.assembler
          asm.with_retry do
            asm.mov(RETR, PTMPR)
          end

          context.ret_reg = RETR
          context.set_reg_content(RETR, self)
          context.ret_node = self
          context.end_using_reg(PTMPR)
          context.end_using_reg(TMPR2)
          
          context = @body.compile(context)
          context
        end
      end

      class SendNewNode<SendNode
        include UnboxedArrayUtil

        add_special_send_node :new

        def initialize(parent, func, arguments, op_flag, seqno)
          super
          allocfunc = MethodSelectNode.new(self, :allocate)
          alloc = SendNode.make_send_node(self, allocfunc, 
                                          arguments[0, 3], 0, seqno)
          allocfunc.set_reciever(alloc)
          initfunc = MethodSelectNode.new(self, :initialize)
          initarg = arguments.dup
          initarg[2] = alloc
          init = SendNode.make_send_node(self, initfunc, 
                                         initarg, op_flag, seqno)
          initfunc.set_reciever(init)
          alloc.parent = init
          @initmethod = init
          @allocmethod = alloc
        end

        def debug_info=(val)
          @initmethod.debug_info = val
          @allocmethod.debug_info = val
          @debug_info = val
        end

        def traverse_childlen
          @arguments.each do |arg|
            yield arg
          end
          yield @func
          yield @initmethod
          yield @body
        end

        def collect_candidate_type_regident(context, slf)
          slfnode = @arguments[2]
          cursig = context.to_signature

          if slf.ruby_type.is_a?(Class) then
            set_escape_node(@parent.is_escape)
            @allocmethod.set_escape_node(@is_escape)
            @initmethod.type = nil
            context = @initmethod.collect_candidate_type(context)
            same_type(self, @allocmethod, cursig, cursig, context)
            context
          else
            super
          end
        end

        def compile_range(context)
          context = gen_alloca(context, 3)
          asm = context.assembler
          breg = context.ret_reg
          
          off = 0
          sig = context.to_signature
          [3, 4, 5].each do |no|
            context = @arguments[no].compile(context)
            rtype = @arguments[no].decide_type_once(sig)
            context = rtype.gen_unboxing(context)
            dst = OpIndirect.new(breg, off)
            asm.with_retry do
              if context.ret_reg.is_a?(OpRegistor) then
                asm.mov(dst, context.ret_reg)
              else
                asm.mov(TMPR, context.ret_reg)
                asm.mov(dst, TMPR)
              end
            end
            off = off + AsmType::MACHINE_WORD.size
          end

          context.ret_reg = breg
          context.ret_node = self
          context
        end

        def compile(context)
          cursig = context.to_signature
          rtype = @arguments[2].decide_type_once(cursig)
          if context.options[:insert_signature_comment] then
            lineno = debug_info[3]
            fname = debug_info[0]
            context.comment[fname] ||= {}
            context.comment[fname][lineno] ||= []
            ent = []
            ent.push 2
            ent.push is_escape
            ent.push rtype
            context.comment[fname][lineno].push ent
          end

          rrtype = rtype.ruby_type
          if rrtype.is_a?(Class) then
            @type = nil
            ctype = decide_type_once(cursig)
            crtype = ctype.ruby_type
            if !ctype.boxed and 
                crtype == Range then
              return compile_range(context)
              
            elsif crtype == Array and
                !ctype.boxed and
                @is_escape != :global_export then
              return compile_array_unboxed(context)

            elsif @initmethod.func.calling_convention(context) then
              context = @initmethod.compile(context)

            else
              # initialize method not defined
              context = @allocmethod.compile(context)
            end
            context.ret_node = self
            @body.compile(context)
          else
            super
          end
        end
      end

      class SendRaiseNode<SendNode
        add_special_send_node :raise

        def compile(context)
          set_exception_handler(context)
          unwindloop = CodeSpace.new
          oldcs = context.set_code_space(unwindloop)
          casm = context.assembler
          handoff = AsmType::MACHINE_WORD.size * 2
          handop = OpIndirect.new(BPR, handoff)
          casm.with_retry do
            casm.push(PROFR)
            casm.call(handop)
            casm.call(unwindloop.var_base_address)
            casm.ret
          end
          context.set_code_space(oldcs)
          casm = context.assembler
          context = @arguments[3].compile(context)
          casm.with_retry do 
            casm.mov(PROFR, context.ret_reg)
            casm.call(unwindloop.var_base_address)
          end

          @body.compile(context)
        end
      end

      class SendPlusNode<SendNode
        include ArithmeticOperationUtil
        include SendUtil
        add_special_send_node :+

        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          case [slf.ruby_type]
          when [Fixnum], [Float], [String], [Array]
            same_type(self, @arguments[2], cursig, cursig, context)
            same_type(self, @arguments[3], cursig, cursig, context)
          else
            same_type(self, @arguments[2], cursig, cursig, context)
          end

          context
        end

#=begin
        def compile(context)
          @arguments[2].type = nil
          cursig = context.to_signature
          rtype = @arguments[2].decide_type_once(cursig)
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
              rrtype == Array or
              rrtype == String or
              @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

          rtype = decide_type_once(cursig)
          rrtype = rtype.ruby_type
          if rrtype == Fixnum then
            context = gen_arithmetic_operation(context, :add, TMPR2, TMPR)
          elsif rrtype == Float then
            context = gen_arithmetic_operation(context, :addsd, XMM4, XMM0)
          else
            raise "Unkown method #{rtype.ruby_type}##{@func.name}"
          end

          @body.compile(context)
        end
#=end
      end

      class SendMinusNode<SendNode
        include ArithmeticOperationUtil
        include SendUtil
        add_special_send_node :-

        def collect_candidate_type_regident(context, slf)
          case [slf.ruby_type]
          when [Fixnum], [Float], [Array]
            cursig = context.to_signature
            same_type(self, @arguments[2], cursig, cursig, context)
            same_type(self, @arguments[3], cursig, cursig, context)
          when [Time]
            cursig = context.to_signature
            ftype = RubyType::BaseType.from_ruby_class(Float)
            add_type(cursig, ftype)
          end

          context
        end

        def compile(context)
          @arguments[2].type = nil
          cursig = context.to_signature
          rtype = @arguments[2].decide_type_once(cursig)
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
              rrtype == Array or
              rrtype == Time or
              @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

          rtype = decide_type_once(cursig)
          rrtype = rtype.ruby_type
          if rrtype == Fixnum then
            context = gen_arithmetic_operation(context, :sub, TMPR2, TMPR)
          elsif rrtype == Float then
            context = gen_arithmetic_operation(context, :subsd, XMM4, XMM0)

          else
            p debug_info
            p rtype
            raise "Unkown method #{rtype.ruby_type}##{@func.name}"
          end

          @body.compile(context)
        end
      end

      class SendMultNode<SendNode
        include ArithmeticOperationUtil
        include SendUtil
        add_special_send_node :*

        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          case [slf.ruby_type]
          when [Fixnum], [Float]
            same_type(self, @arguments[2], cursig, cursig, context)
            same_type(self, @arguments[3], cursig, cursig, context)

          when [String]
            same_type(self, @arguments[2], cursig, cursig, context)
            fixtype = RubyType::BaseType.from_ruby_class(Fixnum)
            @arguments[3].add_type(context.to_signature, fixtype)

          when [Array]
            same_type(self, @arguments[2], cursig, cursig, context)
            fixtype = RubyType::BaseType.from_ruby_class(Fixnum)
            @arguments[3].add_type(context.to_signature, fixtype)
          end

          context
        end

        def compile(context)
          @arguments[2].type = nil
          cursig = context.to_signature
          rtype = @arguments[2].decide_type_once(cursig)
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
              rrtype == String or
              rrtype == Array or
              @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

          rtype = decide_type_once(cursig)
          rrtype = rtype.ruby_type
          if rrtype == Fixnum then
            context = gen_arithmetic_operation(context, :imul, TMPR2, 
                                               TMPR) do |context|
              asm = context.assembler
              if context.ret_reg.is_a?(OpRegistor) then
                asm.with_retry do
                  asm.push(context.ret_reg)
                  asm.mov(DBLLOR, TMPR2)
                  asm.imul(INDIRECT_SPR)
                  asm.add(SPR, AsmType::MACHINE_WORD.size)
                end
              elsif context.ret_reg.is_a?(OpImmidiateMachineWord) then
                asm.with_retry do
                  asm.mov(TMPR, context.ret_reg)
                  asm.push(TMPR)
                  asm.mov(DBLLOR, TMPR2)
                  asm.imul(INDIRECT_SPR)
                  asm.add(SPR, AsmType::MACHINE_WORD.size)
                end
              else
                asm.with_retry do
                  asm.mov(DBLLOR, TMPR2)
                  asm.imul(context.ret_reg)
                end
              end
              context.end_using_reg(context.ret_reg)
            end
              
          elsif rrtype == Float then
            context = gen_arithmetic_operation(context, :mulsd, XMM4, XMM0)
          else
            raise "Unkown method #{rtype.ruby_type}##{@func.name}"
          end

          @body.compile(context)
        end
      end

      class SendDivNode<SendNode
        include ArithmeticOperationUtil
        include SendUtil
        add_special_send_node :/

        def collect_candidate_type_regident(context, slf)
          case [slf.ruby_type]
          when [Fixnum], [Float]
            cursig = context.to_signature
            same_type(self, @arguments[2], cursig, cursig, context)
            same_type(self, @arguments[3], cursig, cursig, context)
          end

          context
        end

        def compile(context)
          @arguments[2].type = nil
          cursig = context.to_signature
          rtype = @arguments[2].decide_type_once(cursig)
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
              @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

          rtype = decide_type_once(cursig)
          rrtype = rtype.ruby_type
          if rrtype == Fixnum then
            context = gen_arithmetic_operation(context, nil, TMPR2, 
                                               TMPR) do |context|
              asm = context.assembler
              asm.with_retry do
                if context.ret_reg == TMPR then
                  asm.push(TMPR)
                  asm.mov(DBLLOR, TMPR2)
                  asm.mov(DBLHIR, DBLLOR)
                  asm.sar(DBLHIR, AsmType::MACHINE_WORD.size * 8 - 1)
                  asm.idiv(INDIRECT_SPR)
                  asm.add(SPR, AsmType::MACHINE_WORD.size)
                elsif context.ret_reg.is_a?(OpImmidiateMachineWord) then
                  asm.mov(TMPR, context.ret_reg)
                  asm.push(TMPR)
                  asm.mov(DBLLOR, TMPR2)
                  asm.mov(DBLHIR, DBLLOR)
                  asm.sar(DBLHIR, AsmType::MACHINE_WORD.size * 8 - 1)
                  asm.idiv(INDIRECT_SPR)
                  asm.add(SPR, AsmType::MACHINE_WORD.size)
                else
                  asm.mov(DBLLOR, TMPR2)
                  asm.mov(DBLHIR, DBLLOR)
                  asm.sar(DBLHIR, AsmType::MACHINE_WORD.size * 8 - 1)
                  asm.idiv(context.ret_reg)
                end
                asm.and(DBLHIR, DBLHIR)
                asm.setnz(DBLHIR)
                asm.neg(DBLHIR)
                asm.and(DBLHIR, DBLLOR)
                asm.setl(DBLHIR)
                asm.sub(DBLLOR, DBLHIR)
                context.end_using_reg(context.ret_reg)
              end
            end
              
          elsif rrtype == Float then
            context = gen_arithmetic_operation(context, :divsd, XMM4, XMM0)
          else
            p debug_info
            raise "Unkown method #{rtype.ruby_type}##{@func.name}"
          end

          @body.compile(context)
        end
      end

      class SendModNode<SendNode
        include ArithmeticOperationUtil
        include SendUtil
        add_special_send_node :%

        def collect_candidate_type_regident(context, slf)
          case [slf.ruby_type]
          when [Fixnum], [Float]
            cursig = context.to_signature
            same_type(self, @arguments[2], cursig, cursig, context)
            same_type(self, @arguments[3], cursig, cursig, context)

          when [String]
            cursig = context.to_signature
            same_type(self, @arguments[2], cursig, cursig, context)

          end

          context
        end

        def compile(context)
          @arguments[2].type = nil
          cursig = context.to_signature
          rtype = @arguments[2].decide_type_once(cursig)
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
              rrtype == String or
              @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

          rtype = decide_type_once(cursig)
          rrtype = rtype.ruby_type
          if rrtype == Fixnum then
            context = gen_arithmetic_operation(context, nil, TMPR2, 
                                               TMPR) do |context|
              asm = context.assembler
              asm.with_retry do
                if context.ret_reg == TMPR then
                  asm.push(TMPR)
                  asm.mov(DBLLOR, TMPR2)
                  asm.mov(DBLHIR, DBLLOR)
                  asm.sar(DBLHIR, AsmType::MACHINE_WORD.size * 8 - 1)
                  asm.idiv(INDIRECT_SPR)
                  asm.add(SPR, AsmType::MACHINE_WORD.size)
                elsif context.ret_reg.is_a?(OpImmidiateMachineWord) then
                  asm.mov(TMPR, context.ret_reg)
                  asm.push(TMPR)
                  asm.mov(DBLLOR, TMPR2)
                  asm.mov(DBLHIR, DBLLOR)
                  asm.sar(DBLHIR, AsmType::MACHINE_WORD.size * 8 - 1)
                  asm.idiv(INDIRECT_SPR)
                  asm.add(SPR, AsmType::MACHINE_WORD.size)
                else
                  asm.mov(DBLLOR, TMPR2)
                  asm.mov(DBLHIR, DBLLOR)
                  asm.sar(DBLHIR, AsmType::MACHINE_WORD.size * 8 - 1)
                  asm.idiv(context.ret_reg)
                end
                asm.and(DBLLOR, DBLLOR)
                asm.setl(DBLLOR)
                asm.neg(DBLLOR)
                asm.xor(DBLHIR, DBLLOR)
                asm.sub(DBLHIR, DBLLOR)
                asm.mov(DBLLOR, DBLHIR)
                context.end_using_reg(context.ret_reg)
              end
            end

          elsif rrtype == Float then
            return super(context)

          else
            raise "Unkown method #{rtype.ruby_type}##{@func.name}"
          end

          @body.compile(context)
        end
      end

      class SendLtLtNode<SendNode
        include SendUtil
        add_special_send_node :<<

        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          case [slf.ruby_type]
          when [Fixnum]
            same_type(self, @arguments[2], cursig, cursig, context)
            same_type(self, @arguments[3], cursig, cursig, context)

          when [Array]
            val = @arguments[3]
            if slf.boxed then
              val.set_escape_node_backward(:global_export)
              context = val.collect_candidate_type(context)
            else
              val.set_escape_node_backward(:local_export)
            end
            arg = [slf, cursig, val, nil, context]
            @arguments[2].add_element_node_backward(arg)
            same_type(self, val, cursig, cursig, context)

          when [String]
            tt = RubyType::BaseType.from_ruby_class(String)
            add_type(cursig, tt)
          end

          context
        end
      end

      class SendGtGtNode<SendNode
        include SendUtil
        add_special_send_node :>>

        def collect_candidate_type_regident(context, slf)
          case [slf.ruby_type]
          when [Fixnum]
            cursig = context.to_signature
            same_type(self, @arguments[2], cursig, cursig, context)
            same_type(self, @arguments[3], cursig, cursig, context)
          end

          context
        end
      end

      class SendAndNode<SendNode
        include SendUtil
        add_special_send_node :&

        def collect_candidate_type_regident(context, slf)
          case [slf.ruby_type]
          when [Fixnum]
            cursig = context.to_signature
            same_type(self, @arguments[2], cursig, cursig, context)
            same_type(self, @arguments[3], cursig, cursig, context)
          end

          context
        end
      end

      class SendOrNode<SendNode
        include SendUtil
        add_special_send_node :|

        def collect_candidate_type_regident(context, slf)
          case [slf.ruby_type]
          when [Fixnum]
            cursig = context.to_signature
            same_type(self, @arguments[2], cursig, cursig, context)
            same_type(self, @arguments[3], cursig, cursig, context)
          end

          context
        end
      end

      class SendXorNode<SendNode
        include SendUtil
        add_special_send_node :^

        def collect_candidate_type_regident(context, slf)
          case [slf.ruby_type]
          when [Fixnum]
            cursig = context.to_signature
            same_type(self, @arguments[2], cursig, cursig, context)
            same_type(self, @arguments[3], cursig, cursig, context)
          end

          context
        end
      end

      class SendNotNode<SendNode
        include SendUtil
        add_special_send_node :~

        def collect_candidate_type_regident(context, slf)
          case [slf.ruby_type]
          when [Fixnum]
            cursig = context.to_signature
            same_type(self, @arguments[2], cursig, cursig, context)
          end

          context
        end
      end

      class SendLengthNode<SendNode
        include SendUtil
        add_special_send_node :length

        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          case [slf.ruby_type]
          when [Array], [String]
            tt = RubyType::BaseType.from_ruby_class(Fixnum)
            add_type(cursig, tt)
          end

          context
        end
      end

      class SendCountNode<SendNode
        include SendUtil
        add_special_send_node :count

        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          case [slf.ruby_type]
          when [String]
            tt = RubyType::BaseType.from_ruby_class(Fixnum)
            add_type(cursig, tt)
          end

          context
        end
      end

      class SendStripExNode<SendNode
        include SendUtil
        add_special_send_node :strip!

        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          case [slf.ruby_type]
          when [String]
            tt = RubyType::BaseType.from_ruby_class(String)
            add_type(cursig, tt)
            tt = RubyType::BaseType.from_ruby_class(NilClass)
            add_type(cursig, tt)
          end

          context
        end
      end

      class SendJoinNode<SendNode
        include SendUtil
        add_special_send_node :join

        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          tt = RubyType::BaseType.from_ruby_class(String)
          add_type(cursig, tt)

          context
        end
      end

      class SendTrExNode<SendNode
        include SendUtil
        add_special_send_node :tr!

        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          case [slf.ruby_type]
          when [String]
            tt = RubyType::BaseType.from_ruby_class(String)
            add_type(cursig, tt)
          end

          context
        end
      end

      class SendOpenNode<SendNode
        include SendUtil
        include SendSingletonClassUtil
        add_special_send_node :open

        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          case [slf.ruby_type]
          when [NilClass], [Object]
            tt = RubyType::BaseType.from_ruby_class(IO)
            add_type(cursig, tt)
          when [Class]
            clsobj = get_singleton_class_object(@arguments[2])
            if clsobj.ruby_type <= IO then
              tt = RubyType::BaseType.from_ruby_class(IO)
              add_type(cursig, tt)
            end
          end

          context
        end
      end

      class SendReadNode<SendNode
        include SendUtil
        add_special_send_node :read

        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          case [slf.ruby_type]
          when [IO], [NilClass], [Object]
            tt = RubyType::BaseType.from_ruby_class(String)
            add_type(cursig, tt)
          end

          context
        end
      end

      class SendGetsNode<SendReadNode
        add_special_send_node :gets
      end

      class SendDirnameNode<SendNode
        include SendUtil
        include SendSingletonClassUtil
        add_special_send_node :dirname

        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          if slf.ruby_type == Class and
              clsobj = get_singleton_class_object(@arguments[2])  and
              clsobj.ruby_type <= File then
            tt = RubyType::BaseType.from_ruby_class(String)
            add_type(cursig, tt)
          end

          context
        end
      end

      class SendCompareNode<SendNode
        include SendUtil
        include CompareOperationUtil
        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          tt = RubyType::BaseType.from_object(true)
          add_type(cursig, tt)
          tt = RubyType::BaseType.from_object(false)
          add_type(cursig, tt)

          context
        end

        def common_compile_compare(context, rtype, fixcmp, flocmp)
          rrtype = rtype.ruby_type
          if rrtype == Fixnum then
            context = gen_compare_operation(context, :cmp, fixcmp, 
                                            TMPR2, TMPR, RETR)
          elsif rrtype == Float then
            context = gen_compare_operation(context, :comisd, flocmp, 
                                            XMM4, XMM0, RETR)
          else
            raise "Unkowwn type #{rtype}"
          end

          context
        end

        def compile(context)
          cursig = context.to_signature
          @arguments[2].type = nil
          rtype = @arguments[2].decide_type_once(cursig)
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
             @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

          if rrtype == Fixnum or rrtype == Float then
            context = gen_eval_self(context)
            context.ret_node.type = nil
            srtype = context.ret_node.decide_type_once(cursig)
            context = srtype.gen_unboxing(context)
            context = compile_compare(context, rtype)
            
          else
            tcon = compile_compare_nonnum(context, rtype)
            if tcon then
              context = tcon
            else
              context = super(context)
            end
          end

          @body.compile(context)
        end

        def compile_compare_nonnum(context, rtype)
          nil
        end
      end

      class SendGtNode<SendCompareNode
        add_special_send_node :<
        def compile_compare(context, rtype)
          common_compile_compare(context, rtype, :setg, :seta)
        end
      end

      class SendGeNode<SendCompareNode
        add_special_send_node :<=
        def compile_compare(context, rtype)
          common_compile_compare(context, rtype, :setge, :setae)
        end
      end

      class SendLtNode<SendCompareNode
        add_special_send_node :>
        def compile_compare(context, rtype)
          common_compile_compare(context, rtype, :setl, :setb)
        end
      end

      class SendLeNode<SendCompareNode
        add_special_send_node :>=
        def compile_compare(context, rtype)
          common_compile_compare(context, rtype, :setle, :setbe)
        end
      end

      class SendEqNode<SendCompareNode
        add_special_send_node :==
        def compile_compare(context, rtype)
          common_compile_compare(context, rtype, :setz, :setz)
        end

        def compile_compare_nonnum(context, rtype)
          if rtype.include_nil? then
            context = gen_eval_self(context)
            if context.ret_reg.is_a?(OpRegXMM) then
              gen_compare_operation(context, :comisd, :setz, 
                                    XMM4, XMM0, RETR)
            else
              gen_compare_operation(context, :cmp, :setz, 
                                    TMPR2, TMPR, RETR, false)
            end
          else
            nil
          end
        end
      end

      class SendEq2Node<SendCompareNode
        add_special_send_node :===
        def compile_compare(context, rtype)
          common_compile_compare(context, rtype, :setz, :setz)
        end

        def compile_compare_nonnum(context, rtype)
          if rtype.include_nil? and false then
            context = gen_eval_self(context)
            if context.ret_reg.is_a?(OpRegXMM) then
              gen_compare_operation(context, :comisd, :setz, 
                                    XMM4, XMM0, RETR)
            else
              gen_compare_operation(context, :cmp, :setz, 
                                    TMPR2, TMPR, RETR, false)
            end
          else
            nil
          end
        end
      end

      class SendNeqNode<SendCompareNode
        add_special_send_node :!=
        def compile_compare(context, rtype)
          common_compile_compare(context, rtype, :setnz, :setnz)
        end

        def compile_compare_nonnum(context, rtype)
          if rtype.include_nil? then
            context = gen_eval_self(context)
            if context.ret_reg.is_a?(OpRegXMM) then
              gen_compare_operation(context, :comisd, :setnz, 
                                    XMM4, XMM0, RETR)
            else
              gen_compare_operation(context, :cmp, :setnz,
                                    TMPR2, TMPR, RETR, false)
            end
          else
            nil
          end
        end
      end

      class SendElementRefNode<SendNode
        include SendUtil
        include UnboxedArrayUtil
        add_special_send_node :[]
        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          case [slf.ruby_type]
          when [Array]
            fixtype = RubyType::BaseType.from_ruby_class(Fixnum)
            idxtype = @arguments[3].decide_type_once(cursig)
            if idxtype.ruby_type == Range or 
                @arguments[4] then
              same_type(self, @arguments[2], cursig, cursig, context)
              return context
            end
            @arguments[3].add_type(cursig, fixtype)
            cidx = @arguments[3].get_constant_value

            # decide type again
            @arguments[2].type = nil
            slf = @arguments[2].decide_type_once(cursig)
#            p debug_info
#            p @arguments[2].type_list(cursig)

            epare = nil

            @arguments[2].element_node_list.each do |ele|
              if ele[3] == cidx and ele[2] != self and 
                  ele[0] == slf then
                epare2 = ele
                esig = epare2[1]
                enode = epare2[2]
                if enode.decide_type_once(esig).ruby_type != Object  then
                  epare = epare2
                  same_type(self, enode, cursig, esig, context)
                end
              end
            end

            if epare == nil then
              @arguments[2].element_node_list.each do |ele|
                if ele[3] == nil and ele[2] != self and 
                    ele[0] == slf then
                  epare2 = ele
                  esig = epare2[1]
                  enode = epare2[2]
                  if enode.decide_type_once(esig).ruby_type != Object then
                    epare = epare2
                    same_type(self, enode, cursig, esig, context)
                  end
                end
              end
            end

=begin
            if epare == nil then
              @arguments[2].element_node_list.each do |ele|
                if ele[3] == cidx and ele[2] != self and 
                    ele[0].ruby_type == slf.ruby_type then
                  epare2 = ele
                  esig = epare2[1]
                  enode = epare2[2]
                  if enode.decide_type_once(esig).ruby_type != Object then
                    epare = epare2
                    same_type(self, enode, cursig, esig, context)
                  end
                end
              end
            end

            if epare == nil then
              nele = @arguments[2].element_node_list.select {|e| e[3] == nil}
              if nele.size == 1 then
                epare = nele[0]
                esig = epare[1]
                enode = epare[2]
                same_type(self, enode, cursig, esig, context)
              end
            end
=end

            if epare == nil then
              if slf.have_element? and 
                  slf.element_type and 
                  slf.element_type[nil] and 
                  slf.element_type[nil][0] then
                add_type(cursig, slf.element_type[nil][0])
              else
                p "foo"
              end
            end
            @type = nil
            
          when [Hash]
            cidx = @arguments[3].get_constant_value
            rtype = @arguments[2].decide_type_once(cursig)
            niltype = RubyType::BaseType.from_ruby_class(NilClass)
            @arguments[3].type = nil
            @arguments[3].add_type(cursig, niltype)
            @arguments[2].add_element_node(rtype, cursig, self, cidx, context)

          when [String]
            tt = RubyType::BaseType.from_ruby_class(String)
            add_type(cursig, tt)
          end

          context
        end

        def compile(context)
          sig = context.to_signature
          asm = context.assembler
#          @arguments[2].type = nil
          rtype = @arguments[2].decide_type_once(sig)
          rrtype = rtype.ruby_type

          if rrtype == Array and !rtype.boxed and 
              @arguments[2].is_escape != :global_export then
            context = gen_ref_element(context, @arguments[2], @arguments[3])
#            @type = nil
            rtype = decide_type_once(sig)
            if rtype.ruby_type == Float and !rtype.boxed then
              asm.with_retry do
                asm.mov(XMM0, context.ret_reg)
              end
              context.ret_reg = XMM0
              context.set_reg_content(XMM0, self)
            else
              asm.with_retry do
                asm.mov(RETR, context.ret_reg)
              end
              context.ret_reg = RETR
              context.set_reg_content(RETR, self)
            end
            @body.compile(context)
          else
=begin
            p @arguments[2].type
            p @arguments[2].instance_eval {@type_list}
              p sig
            p @arguments[2].is_escape
            p debug_info
=end
            super
          end
        end
      end

      class SendElementAssignNode<SendNode
        include SendUtil
        include UnboxedArrayUtil
        add_special_send_node :[]=
        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          case [slf.ruby_type]
          when [Array]
            fixtype = RubyType::BaseType.from_ruby_class(Fixnum)
            val = @arguments[4]
            @arguments[3].add_type(cursig, fixtype)
            cidx = @arguments[3].get_constant_value
            @arguments[2].type = nil
            slf = @arguments[2].decide_type_once(cursig)

            val.type = nil
            if slf.boxed and @arguments[2].is_escape == :global_export then
              val.set_escape_node_backward(:global_export)
              context = val.collect_candidate_type(context)
            else
              val.set_escape_node_backward(:local_export)
            end
            arg = [slf, cursig, val, cidx, context]
            @arguments[2].add_element_node_backward(arg)

            same_type(self, val, cursig, cursig, context)

          when [Hash]
            cidx = @arguments[3].get_constant_value
            @arguments[2].add_element_node(slf, cursig, self, cidx, context)
            niltype = RubyType::BaseType.from_ruby_class(NilClass)
            @arguments[3].type = nil
            @arguments[3].add_type(cursig, niltype)
            @arguments[4].type = nil
            @arguments[4].add_type(cursig, niltype)
            @arguments[3].set_escape_node_backward(:global_export)
            @arguments[4].set_escape_node_backward(:global_export)
          end

          context
        end

        def compile(context)
          sig = context.to_signature
          rtype = @arguments[2].decide_type_once(sig)
          rrtype = rtype.ruby_type
          if rrtype == Array and !rtype.boxed and 
              @arguments[2].is_escape != :global_export then
            context = gen_set_element(context, 
                                      @arguments[2], 
                                      @arguments[3], 
                                      @arguments[4])
            @body.compile(context)
          else
            super
          end
        end
      end

      class Send__ID__Node<SendNode
        add_special_send_node :__id__

        def collect_candidate_type_regident(context, slf)
          sig = context.to_signature
          fixnumtype = RubyType::BaseType.from_ruby_class(Fixnum)
          add_type(sig, fixnumtype)
          context
        end
      end

      class SendToFNode<SendNode
        include AbsArch

        add_special_send_node :to_f

        def collect_candidate_type_regident(context, slf)
          sig = context.to_signature
          floattype = RubyType::BaseType.from_ruby_class(Float)
          add_type(sig, floattype)
          context
        end

        def compile(context)
#          @arguments[2].type = nil
          @arguments[2].decide_type_once(context.to_signature)
          rtype = @arguments[2].type
          rrtype = rtype.ruby_type
          if rrtype == Fixnum then
            context = gen_eval_self(context)
            context = rtype.gen_unboxing(context)
            asm = context.assembler
            if context.ret_reg.is_a?(OpRegistor) or
                 context.ret_reg.is_a?(OpIndirect) then
              asm.with_retry do
                asm.cvtsi2sd(XMM0, context.ret_reg)
              end
            else
              asm.with_retry do
                asm.mov(TMPR, context.ret_reg)
                asm.cvtsi2sd(XMM0, TMPR)
              end
            end
            context.ret_node = self
            context.ret_reg = XMM0
            context
          else
            super(context)
          end
        end
      end

      class SendToINode<SendNode
        add_special_send_node :to_i
        def collect_candidate_type_regident(context, slf)
          sig = context.to_signature
          fixnumtype = RubyType::BaseType.from_ruby_class(Fixnum)
          add_type(sig, fixnumtype)
          context
        end

        def compile(context)
#          @arguments[2].type = nil
          @arguments[2].decide_type_once(context.to_signature)
          rtype = @arguments[2].type
          rrtype = rtype.ruby_type
          if rrtype == Float then
            context = gen_eval_self(context)
            context = rtype.gen_unboxing(context)
            asm = context.assembler
            if context.ret_reg.is_a?(OpRegistor) or
                 context.ret_reg.is_a?(OpIndirect) then
              asm.with_retry do
                asm.cvttsd2si(RETR, context.ret_reg)
              end
            else
              asm.with_retry do
                asm.mov(XMM0, context.ret_reg)
                asm.cvttsd2si(RETR, XMM0)
              end
            end
            context.set_reg_content(RETR, self)
            context.ret_node = self
            context.ret_reg = RETR
            context
          else
            super(context)
          end
        end
      end

      class SendChrNode<SendNode
        add_special_send_node :chr
        def collect_candidate_type_regident(context, slf)
          sig = context.to_signature
          strtype = RubyType::BaseType.from_ruby_class(String)
          add_type(sig, strtype)
          context
        end
      end

      class SendNowNode<SendNode
        add_special_send_node :now
        def collect_candidate_type_regident(context, slf)
          sig = context.to_signature
          timetype = RubyType::BaseType.from_ruby_class(Time)
          add_type(sig, timetype)
          context
        end
      end

      class SendAMNode<SendNode
        add_special_send_node :-@
        def collect_candidate_type_regident(context, slf)
          sig = context.to_signature
          same_type(self, @arguments[2], sig, sig, context)
          context
        end

        def compile(context)
#          @arguments[2].type = nil
          @arguments[2].decide_type_once(context.to_signature)
          rtype = @arguments[2].type
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
              @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

          context = gen_eval_self(context)
          context = rtype.gen_unboxing(context)
          asm = context.assembler
          if rrtype == Fixnum then
            asm.with_retry do
              asm.mov(RETR, context.ret_reg)
              asm.neg(RETR)
            end
            context.set_reg_content(RETR, self)
            context.ret_reg = RETR
          elsif rrtype == Float then
            context.start_using_reg(XMM4)
            asm.with_retry do
              asm.mov(XMM4, context.ret_reg)
              asm.subsd(XMM0, XMM0)
              asm.subsd(XMM0, XMM4)
            end
            context.ret_reg = XMM0
            context.set_reg_content(XMM0, self)
            context.end_using_reg(XMM4)
          end
          context.ret_node = self

          if rtype.boxed then
            context = rtype.to_unbox.gen_boxing(context)
          end
          @body.compile(context)
        end
      end

      class SendRandNode<SendNode
        add_special_send_node :rand
        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          if @arguments[3] then
            # when argument is 0, type is Float
            # but ignor it by current version
            context = @arguments[3].collect_candidate_type(context)
            tt = RubyType::BaseType.from_ruby_class(Fixnum)
          else
            tt = RubyType::BaseType.from_ruby_class(Float)
          end
          add_type(cursig, tt)
          context
        end

        def compile(context)
          addr = lambda {
            fname = "rb_genrand_real"
            a = address_of(fname)
            $symbol_table[a] = fname
            a
          }
          fadd = OpVarMemAddress.new(addr)
          context.start_arg_reg(FUNC_FLOAT_ARG)
          context.start_arg_reg
          asm = context.assembler
          case $ruby_platform
          when /x86_64/
            asm.with_retry do
              asm.call(fadd)
            end

          when /i.86/
            asm.with_retry do
              asm.call(fadd)
              asm.sub(SPR, 8)
              asm.fstpl(INDIRECT_SPR)
              asm.pop(XMM0)
            end
          end
          context.end_arg_reg
          context.end_arg_reg(FUNC_FLOAT_ARG)
          context.ret_reg = XMM0
          context
        end
      end

      class SendRangeAccessNode<SendNode
        include AbsArch

        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          if slf.ruby_type == Range then
            epare = @arguments[2].element_node_list[0]
            esig = epare[1]
            enode = epare[2]
            tt = enode.decide_type_once(esig)
            add_type(cursig, tt)
          else
            super
          end

          context
        end

        def compile(context)
          cursig = context.to_signature
          @arguments[2].type = nil
          rtype = @arguments[2].decide_type_once(cursig)
          rrtype = rtype.ruby_type
          decide_type_once(cursig)
          if rrtype == Range and !rtype.boxed then
            context = @arguments[2].compile(context)
            slotoff = OpIndirect.new(TMPR, arg_offset)
            asm = context.assembler
            asm.with_retry do
              asm.mov(TMPR, context.ret_reg)
              asm.mov(RETR, slotoff)
            end

            context.ret_reg = RETR
            context.set_reg_content(RETR, self)
            context.ret_node = self

            context
          else
            super(context)
          end
        end
      end

      class SendFirstNode<SendRangeAccessNode
        add_special_send_node :first
        def arg_offset
          0
        end
      end

      class SendLastNode<SendRangeAccessNode
        add_special_send_node :last
        def arg_offset
          AsmType::MACHINE_WORD.size
        end
      end

      class SendExcludeEndNode<SendRangeAccessNode
        add_special_send_node :exclude_end?
        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          if slf.ruby_type == Range then
            tt = RubyType::BaseType.from_ruby_class(TrueClass)
            add_type(cursig, tt)
            tt = RubyType::BaseType.from_ruby_class(FalseClass)
            add_type(cursig, tt)
          else
            super
          end

          context
        end

        def arg_offset
          AsmType::MACHINE_WORD.size * 2
        end
      end

      class SendSizeNode<SendNode
        include SendUtil
        include UnboxedArrayUtil
        add_special_send_node :size
        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          tt = RubyType::BaseType.from_ruby_class(Fixnum)
          add_type(cursig, tt)
          context
        end

        def compile(context)
          sig = context.to_signature
          asm = context.assembler
          rtype = @arguments[2].decide_type_once(sig)
          rrtype = rtype.ruby_type
          if rrtype == Array and !rtype.boxed and 
              @arguments[2].is_escape != :global_export then
            context = gen_ref_element(context, @arguments[2], -1)
            asm.with_retry do
              asm.mov(RETR, context.ret_reg)
            end
            context.ret_reg = RETR
            context.set_reg_content(RETR, self)
            @body.compile(context)
          else
            super
          end
        end
      end

      class SendSameArgTypeNode<SendNode
        def collect_candidate_type_regident(context, slf)
          sig = context.to_signature
          same_type(self, @arguments[3], sig, sig, context)
          context
        end
      end

      class SendIsANode<SendNode
        add_special_send_node :is_a?

        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          tt = RubyType::BaseType.from_ruby_class(TrueClass)
          add_type(cursig, tt)
          tt = RubyType::BaseType.from_ruby_class(FalseClass)
          add_type(cursig, tt)
          context
        end
        
        def compile(context)
          cursig = context.to_signature
          @arguments[2].type = nil
          rtype = @arguments[2].decide_type_once(cursig)
          rrtype = rtype.ruby_type
          ertype = @arguments[3].get_constant_value
          ertype = ertype ? ertype[0] : nil
          if rrtype <= ertype then
            context.ret_reg = 2
          else
            context.ret_reg = 0
          end
          context
        end
      end

      class SendDispTypeNode<SendNode
        add_special_send_node :disp_type
        def collect_candidate_type_regident(context, slf)
#=begin
          sig = context.to_signature
          p debug_info
          p sig
          p @arguments[2].type_list(sig)
          @arguments[2].type = nil
          p @arguments[2].decide_type_once(sig)
          #          p @arguments[2].instance_eval {@type_list}
          p @arguments[2].is_escape
          p @arguments[2].class
#=end
          context
        end
        
        def compile(context)
=begin
             sig = context.to_signature
             p debug_info
             p sig
             p @arguments[2].type_list(sig)
             @arguments[2].type = nil
             p @arguments[2].decide_type_once(sig)
             #          p @arguments[2].instance_eval {@type_list}
             p @arguments[2].is_escape
             p @arguments[2].class
=end
          @body.compile(context)
        end
      end

      class SendSelfOfCallerTypeNode<SendNode
        include NodeUtil
        add_special_send_node :self_of_caller
        
        def initialize(parent, func, arguments, op_flag, seqno)
          super
          @frame_info = search_frame_info
        end
        
        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          callersig = context.to_signature(-2)
          tt = callersig[2]
          add_type(cursig, tt)
          context
        end
        
        def compile(context)
          asm = context.assembler
          prevenv = @frame_info.offset_arg(0, BPR)
          # offset of self is common, so it no nessery traverse 
          # prev frame for @frame_info.
          slfarg = @frame_info.offset_arg(2, TMPR2)
          context.start_using_reg(TMPR2)
          asm.with_retry do
            asm.mov(TMPR2, prevenv)
            asm.mov(RETR, slfarg)
          end
          context.end_using_reg(TMPR2)
          context.ret_reg = RETR
          context.ret_node = self
          @body.compile(context)
        end
      end

      class SendSameSelfTypeNode<SendNode
        def collect_candidate_type_regident(context, slf)
          sig = context.to_signature
          same_type(self, @arguments[2], sig, sig, context)
          context
        end
      end

      class SendDupNode<SendSameSelfTypeNode
        add_special_send_node :dup
        
        def compile(context)
          sig = context.to_signature
          rtype = @arguments[2].decide_type_once(sig)
          rrtype = rtype.ruby_type
          context = @arguments[2].compile(context)
          context = rtype.gen_copy(context)
          @body.compile(context)
        end
      end

      class SendCloneNode<SendDupNode
        add_special_send_node :clone
      end

      class SendSortNode<SendSameSelfTypeNode
        add_special_send_node :sort
      end

      class SendUniqExNode<SendSameSelfTypeNode
        add_special_send_node :uniq!
      end

      class SendSliceExNode<SendSameSelfTypeNode
        add_special_send_node :slice!
      end

      class SendReverseNode<SendSameSelfTypeNode
        add_special_send_node :reverse
      end

      class SendReverseNode<SendSameSelfTypeNode
        add_special_send_node :reverse!
      end
 
      class SendScanNode<SendNode
        add_special_send_node :scan
        def collect_candidate_type_regident(context, slf)
          sig = context.to_signature
          type = RubyType::BaseType.from_ruby_class(Array)
          add_type(sig, type)
          context
        end
      end

      class SendMathFuncNode<SendNode
        include SendUtil
        def collect_candidate_type_regident(context, slf)
          sig = context.to_signature
          floattype = RubyType::BaseType.from_ruby_class(Float)
          add_type(sig, floattype)
          context
        end

        def compile_call_func(context, fname)
          addr = lambda { 
            a = address_of(fname)
            $symbol_table[a] = fname
            a
          }
          fadd = OpVarMemAddress.new(addr)
          context.start_arg_reg(FUNC_FLOAT_ARG)
          context.start_arg_reg
          asm = context.assembler
          asm.with_retry do
            asm.mov(FUNC_FLOAT_ARG[0], context.ret_reg)
          end
          context.set_reg_content(FUNC_FLOAT_ARG[0].dst_opecode, 
                                  context.ret_node)
          case $ruby_platform
          when /x86_64/
            asm.with_retry do
              asm.call_with_arg(fadd, 1)
            end

          when /i.86/
            asm.with_retry do
              asm.call_with_arg(fadd, 1)
              asm.sub(SPR, 8)
              asm.fstpl(INDIRECT_SPR)
              asm.pop(XMM0)
            end
          end
          context.end_arg_reg
          context.end_arg_reg(FUNC_FLOAT_ARG)
          context
        end

        def compile(context)
          @arguments[2].decide_type_once(context.to_signature)
          rtype = @arguments[2].type
          rrtype = rtype.ruby_type
          if rtype.ruby_type.is_a?(RubyType::DefaultType0) or
             @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

          context = @arguments[2].compile(context)
          @arguments[3].decide_type_once(context.to_signature)
          rtype = @arguments[3].type
          context = @arguments[3].compile(context)
          if rtype.ruby_type == Fixnum then
            asm = context.assembler
            if context.ret_reg.is_a?(OpRegistor) then
              if !context.ret_reg.is_a?(OpRegXMM) then
                asm.with_retry do
                  asm.cvtsi2sd(XMM0, context.ret_reg)
                end
                context.ret_reg = XMM0
              end
            else
              asm.with_retry do
                asm.mov(TMPR, context.ret_reg)
                asm.cvtsi2sd(XMM0, TMPR)
              end
              context.ret_reg = XMM0
            end
          end
          context = rtype.gen_unboxing(context)
          context = compile_main(context)
          @body.compile(context)
        end
      end
      
      class SendSqrtNode<SendMathFuncNode
        add_special_send_node :sqrt
        def compile_main(context)
          context = compile_call_func(context, "sqrt")
          context.ret_node = self
          context.ret_reg = XMM0
          context
        end
      end

      class SendSinNode<SendMathFuncNode
        add_special_send_node :sin
        def compile_main(context)
          context = compile_call_func(context, "sin")
          context.ret_node = self
          context.ret_reg = XMM0
          context
        end
      end

      class SendCosNode<SendMathFuncNode
        add_special_send_node :cos
        def compile_main(context)
          context = compile_call_func(context, "cos")
          context.ret_node = self
          context.ret_reg = XMM0
          context
        end
      end

      class SendTanNode<SendMathFuncNode
        add_special_send_node :tan
        def compile_main(context)
          context = compile_call_func(context, "tan")
          context.ret_node = self
          context.ret_reg = XMM0
          context
        end
      end

      class SendLogNode<SendMathFuncNode
        add_special_send_node :log
        def compile_main(context)
          context = compile_call_func(context, "log")
          context.ret_node = self
          context.ret_reg = XMM0
          context
        end
      end

      class RawSendNode<SendNode
        def collect_candidate_type(context)
          @arguments.each do |arg|
            context = arg.collect_candidate_type(context)
          end

          context = collect_candidate_type_body(context)

          @body.collect_candidate_type(context)
        end
      end

      class RetStringSendNode<RawSendNode
        def collect_candidate_type_body(context)
          sig = context.to_signature
          tt = RubyType::BaseType.from_ruby_class(String)
          add_type(sig, tt)

          context
        end
      end

      class RetToregexpSendNode<RawSendNode
        def collect_candidate_type_body(context)
          sig = context.to_signature
          tt = RubyType::BaseType.from_ruby_class(Regexp)
          add_type(sig, tt)

          context
        end
      end

      class RetBackrefSendNode<RawSendNode
        def collect_candidate_type_body(context)
          sig = context.to_signature
          tt = RubyType::BaseType.from_ruby_class(Object)
          add_type(sig, tt)

          context
        end
      end

      class RetNthMatchSendNode<RawSendNode
        def collect_candidate_type_body(context)
          sig = context.to_signature
          tt = RubyType::BaseType.from_ruby_class(String)
          add_type(sig, tt)

          context
        end
      end

      class RetArraySendNode<RawSendNode
        include AbsArch
        include UnboxedArrayUtil

        def collect_candidate_type_body(context)
          sig = context.to_signature
          tt = RubyType::BaseType.from_ruby_class(Array)
          if context.options[:compile_array_as_uboxed] and
              @element_node_list.size > 1 and 
                @element_node_list[1..-1].all? {|e|
                  e[3] or e[2].class == BaseNode
                } then
            tt = tt.to_unbox
          end

          add_type(sig, tt)
          @type = nil
          tt = decide_type_once(sig)

          @arguments[1..-1].each_with_index do |anode, idx|
            add_element_node(tt, sig, anode, [idx], context)
          end

          context
        end

        def compile(context)
          sig = context.to_signature
          rtype = decide_type_once(sig)
          rrtype = rtype.ruby_type
          if rrtype == Array and 
              !rtype.boxed and 
              @is_escape != :global_export then
            sizent = @element_node_list[1..-1].max_by {|a| a[3] ? a[3][0] : -1}
            siz = sizent[3][0] + 2
            context = gen_alloca(context, siz)

            context.start_using_reg(TMPR2)
            asm = context.assembler
            asm.with_retry do
              asm.mov(TMPR2, THEPR)
              asm.mov(INDIRECT_TMPR2, siz - 1)
              asm.add(TMPR2, 8)
            end
            context.set_reg_content(TMPR2, THEPR)

            @arguments[1..-1].each_with_index do |anode, idx|
              context = gen_set_element(context, nil, idx, anode)
            end

            asm.with_retry do
              asm.mov(RETR, TMPR2)
            end
            context.end_using_reg(TMPR2)

            context.ret_reg = RETR
            context.set_reg_content(RETR, self)
            context.ret_node = self
            @body.compile(context)
          else
            super
          end
        end
      end
    end
  end
end
