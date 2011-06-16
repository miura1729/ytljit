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

        def self.macro_expand(context, func, arguments, op_flag, seqno)
          if @@macro_tab[func.name] and 
              (op_flag & (0b11 << 3)) != 0 then
            cclsnode = context.current_class_node
            if context.current_method_node == nil then
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

        attr_accessor :current_exception_table

        def traverse_childlen
          @arguments.each do |arg|
            yield arg
          end
          yield @func
          yield @body
        end

        def get_send_method_node(cursig)
          mt = nil
#          @arguments[2].type = nil
          slf = @arguments[2].decide_type_once(cursig)
          if slf.instance_of?(RubyType::DefaultType0) then
            # Chaos
          end

          if is_fcall or is_vcall then
            mt = @func.method_top_node(@class_top, nil)

          else

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

          @modified_local_var    = context.modified_local_var.last.dup
          @modified_instance_var = context.modified_instance_var.dup

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

        def collect_candidate_type(context)
          cursig = context.to_signature

          # get saved original signature
          metsigent = search_signature(cursig)
          oldsignat = nil
          if metsigent then
            oldsignat = metsigent[1]
          end

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
          changed = check_signature_changed(context, signat, metsigent, cursig)

          mt, slf = get_send_method_node(cursig)
          if mt then
            if changed then
              mt.type_list(metsigent[1])[1] = []
              mt.ti_reset
            end

            context = mt.collect_candidate_type(context, @arguments, signat)

            same_type(self, mt, cursig, signat, context)

            context.push_signature(@arguments, mt)
            if blknode.is_a?(TopNode) then
              # Have block
              mt.yield_node.map do |ynode|
                yargs = ynode.arguments.dup
                ysignat = ynode.signature(context)

                same_type(ynode, blknode, signat, ysignat, context)

                # inherit self from caller node
                yargs[2] = context.current_method_signature_node[-2][2]
                ysignat[2] = cursig[2]
                if yargs[2].decide_type_once(cursig).ruby_type == Object then
                  context.current_method_signature_node.reverse.each {|e0| 
                    if e0[2].class == SendNewArenaNode then
                      if yargs[2].type then
                        yargs[2] = e0[2]
                        ysignat[2] = yargs[2].type
                      end
                      break
                    end
                  }
                end
                context = blknode.collect_candidate_type(context, 
                                                         yargs, ysignat)

              end
            else
              context = blknode.collect_candidate_type(context)
            end
            context.pop_signature
            
          else
            context = collect_candidate_type_regident(context, slf)
          end

          @body.collect_candidate_type(context)
        end

        def compile(context)
          context = super(context)

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
            context = compile_ytl(context)

          when nil

          else
            raise "Unsupported calling conversion #{callconv}"
          end
          
          decide_type_once(context.to_signature)
          if @type.is_a?(RubyType::RubyTypeUnboxed) and 
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

      class SendIncludeCommonNode<SendNode
        def collect_candidate_type_regident(context, slf)
          slfnode = @arguments[2]
          rtype = slfnode.decide_type_once(context.to_signature)
          add_type(context.to_signature, rtype)
          modnode = @arguments[3].value_node

          add_search_module(slfnode, modnode)
          context
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

        add_special_send_node :allocate

        def collect_candidate_type_regident(context, slf)
          slfnode = @arguments[2]
          cursig = context.to_signature
          if slf.ruby_type.is_a?(Class) then
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

            clt =  ClassTopNode.get_class_top_node(tt.ruby_type_raw)
            if context.options[:compile_array_as_uboxed] and
                @is_escape and @is_escape != :global_export and
                (clt and  !clt.body.is_a?(DummyNode)) then
              tt = tt.to_unbox
            elsif type_list(cursig)[0].include?(tt.to_unbox) then
              type_list(cursig)[0] = []
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
            @is_escape = search_class_top.is_escape
            @allocmethod.is_escape = @is_escape
            case slfnode
            when ConstantRefNode
              context = @initmethod.collect_candidate_type(context)
              clstop = slfnode.value_node
              tt = nil
              case clstop
              when ClassTopNode
                tt = RubyType::BaseType.from_ruby_class(clstop.klass_object)
                
              when LiteralNode
                tt = RubyType::BaseType.from_ruby_class(clstop.value)

              else
                raise "Unkown node type in constant #{slfnode.value_node.class}"
              end

              clt =  ClassTopNode.get_class_top_node(tt.ruby_type_raw)
              if context.options[:compile_array_as_uboxed] and
                  @is_escape and @is_escape != :global_export and
                  (clt and  !clt.body.is_a?(DummyNode)) then
                tt = tt.to_unbox
              elsif type_list(cursig)[0].include?(tt.to_unbox) then
                type_list(cursig)[0] = []
              end

              # set element type
              if tt.ruby_type == Range then
                tt.args = @arguments[3..-1]
                add_element_node(tt, cursig, @arguments[3], [0], context)
                add_element_node(tt, cursig, @arguments[4], [1], context)

              elsif tt.ruby_type == Array then
                if context.options[:compile_array_as_uboxed] and
                    @element_node_list.size > 1 and
                      @element_node_list[1..-1].all? {|e|
                        e[3]
                      } and 
                    @is_escape and @is_escape != :global_export then
                  tt = tt.to_unbox
                end
                if @arguments[4] then
                  siz = @arguments[3].get_constant_value
                  if siz and false then
                    # Here is buggy yet Fix me
                    siz[0].times do |i|
                      add_element_node(tt, cursig, @arguments[4], [i], context)
                    end
                  else
                    add_element_node(tt, cursig, @arguments[4], nil, context)
                  end
                end
              end

              add_type(cursig, tt)
            else
              raise "Unkonwn node type #{@arguments[2].class} "
            end
          end
          context
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
          rtype = @arguments[2].decide_type_once(context.to_signature)
          rrtype = rtype.ruby_type
          if rrtype.is_a?(Class) then
            ctype = decide_type_once(context.to_signature)
            crtype = ctype.ruby_type
            if @is_escape != :global_export and 
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

      class SendPlusNode<SendNode
        include ArithmeticOperationUtil
        include SendUtil
        add_special_send_node :+

        def collect_candidate_type_regident(context, slf)
          case [slf.ruby_type]
          when [Fixnum], [Float], [String], [Array]
            cursig = context.to_signature
            same_type(self, @arguments[2], cursig, cursig, context)
            same_type(self, @arguments[3], cursig, cursig, context)
          end

          context
        end

#=begin
        def compile(context)
          @type = nil
          rtype = decide_type_once(context.to_signature)
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
              rrtype == Array or
              @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

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
          end

          context
        end

        def compile(context)
          @type = nil
          rtype = decide_type_once(context.to_signature)
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
              rrtype == Array or
              @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

          if rrtype == Fixnum then
            context = gen_arithmetic_operation(context, :sub, TMPR2, TMPR)
          elsif rrtype == Float then
            context = gen_arithmetic_operation(context, :subsd, XMM4, XMM0)

          else
            p debug_info
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
          end

          context
        end

        def compile(context)
          @type = nil
          rtype = decide_type_once(context.to_signature)
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
             @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

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
          @type = nil
          rtype = decide_type_once(context.to_signature)
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
              @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

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
          when [Fixnum]
            cursig = context.to_signature
            same_type(self, @arguments[2], cursig, cursig, context)
            same_type(self, @arguments[3], cursig, cursig, context)
          end

          context
        end

        def compile(context)
          @type = nil
          rtype = decide_type_once(context.to_signature)
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
              @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

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
          else
            raise "Unkown method #{rtype.ruby_type}##{@func.name}"
          end

          @body.compile(context)
        end
      end

      class SendLtLtNode<SendNode
        include ArithmeticOperationUtil
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
            arg = [slf, cursig, val, nil, context]
            @arguments[2].add_element_node_backward(arg)
            same_type(self, val, cursig, cursig, context)
          end

          context
        end
      end

      class SendGtGtNode<SendNode
        include ArithmeticOperationUtil
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
        include ArithmeticOperationUtil
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
          rtype = @arguments[2].decide_type_once(context.to_signature)
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
             @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

          if rrtype == Fixnum or rrtype == Float then
            context = gen_eval_self(context)
            context.ret_node.type = nil
            srtype = context.ret_node.decide_type_once(context.to_signature)
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
      end

      def compile_compare_nonnum(context, rtype)
        nil
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
            gen_compare_operation(context, :cmp, :setz, 
                                  TMPR2, TMPR, RETR, false)
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
            gen_compare_operation(context, :cmp, :setnz,
                                  TMPR2, TMPR, RETR, false)
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
            if idxtype.ruby_type == Range then
              same_type(self, @arguments[2], cursig, cursig, context)
              return context
            end
            @arguments[3].add_type(cursig, fixtype)
            cidx = @arguments[3].get_constant_value

            # decide type again
            @arguments[2].type = nil
            slf = @arguments[2].decide_type_once(cursig)

            epare = nil

            @arguments[2].element_node_list.each do |ele|
              if ele[3] == cidx and ele[2] != self and ele[0] == slf then
                epare2 = ele
                esig = epare2[1]
                enode = epare2[2]
                unless enode.type_list(esig) == [[], []]
                  epare = epare2
                  same_type(self, enode, cursig, esig, context)
                end
              end
            end

            if epare == nil then
              @arguments[2].element_node_list.each do |ele|
                if ele[3] == nil and ele[2] != self and ele[0] == slf then
                  epare2 = ele
                  esig = epare2[1]
                  enode = epare2[2]
                  unless enode.type_list(esig) == [[], []]
                    epare = epare2
                    same_type(self, enode, cursig, esig, context)
                  end
                end
              end
            end
#=begin
            if epare == nil and false then
              @arguments[2].element_node_list.each do |ele|
                if ele[3] == cidx and ele[2] != self and 
                    ele[0].ruby_type == slf.ruby_type then
                  epare2 = ele
                  esig = epare2[1]
                  enode = epare2[2]
                  unless enode.type_list(esig) == [[], []]
                    epare = epare2
                    same_type(self, enode, cursig, esig, context)
#                    break
                  end
                end
              end
            end
#=end
            if epare == nil then
              nele = @arguments[2].element_node_list.select {|e| e[3] == nil}
              if nele.size == 1 then
                epare = @arguments[2].element_node_list[0]
                esig = epare[1]
                enode = epare[2]
                same_type(self, enode, cursig, esig, context)
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
          end

          context
        end

        def compile(context)
          sig = context.to_signature
          asm = context.assembler
          rtype = @arguments[2].decide_type_once(sig)
          rrtype = rtype.ruby_type

          if rrtype == Array and !rtype.boxed and 
              @arguments[2].is_escape != :global_export then
            context = gen_ref_element(context, @arguments[2], @arguments[3])
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
            @body.compile(context)
          else
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
          rtype = nil
          case [slf.ruby_type]
          when [Array]
            fixtype = RubyType::BaseType.from_ruby_class(Fixnum)
            val = @arguments[4]
            val.is_escape = :local_export
            @arguments[3].add_type(cursig, fixtype)
            cidx = @arguments[3].get_constant_value
            @arguments[2].type = nil
            slf = @arguments[2].decide_type_once(cursig)

            arg = [slf, cursig, val, cidx, context]
            @arguments[2].add_element_node_backward(arg)

            epare = nil
            @arguments[2].element_node_list.each do |ele|
              if ele[3] == cidx and ele[2] != self then
                epare = ele
                break
              end
            end
            if epare == nil then
              epare = @arguments[2].element_node_list[0]
              @arguments[2].element_node_list.each do |ele|
                if ele[3] == nil and ele[2] != self and ele[0] == slf then
                  epare = ele
                  break
                end
              end
            end

            esig = epare[1]
            enode = epare[2]
            if enode != self then
              same_type(self, enode, cursig, esig, context)
            end
            if slf.boxed then
              @arguments[4].set_escape_node_backward(:global_export)
            else
              @arguments[4].set_escape_node_backward(:local_export)
            end

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

      class SendAMNode<SendNode
        add_special_send_node :-@
        def collect_candidate_type_regident(context, slf)
          sig = context.to_signature
          same_type(self, @arguments[2], sig, sig, context)
          context
        end

        def compile(context)
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
            context.ret_reg = RETR
          elsif rrtype == Float then
            context.start_using_reg(XMM4)
            asm.with_retry do
              asm.mov(XMM4, context.ret_reg)
              asm.subsd(XMM0, XMM0)
              asm.subsd(XMM0, XMM4)
            end
            context.ret_reg = XMM0
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
          sig = context.to_signature
          floattype = RubyType::BaseType.from_ruby_class(Float)
          add_type(sig, floattype)
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
          sig = context.to_signature
          rtype = @arguments[2].decide_type_once(sig)
          rrtype = rtype.ruby_type
          decide_type_once(sig)
          if rrtype == Range and !rtype.boxed and 
              @arguments[2].is_escape != :global_export then
            context = @arguments[2].compile(context)
            slotoff = OpIndirect.new(TMPR, arg_offset)
            asm = context.assembler
            asm.with_retry do
              asm.mov(TMPR, context.ret_reg)
              asm.mov(RETR, slotoff)
            end

            context.ret_reg = RETR
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
        add_special_send_node :size
        def collect_candidate_type_regident(context, slf)
          cursig = context.to_signature
          tt = RubyType::BaseType.from_ruby_class(Fixnum)
          add_type(cursig, tt)
          context
        end
      end

      class SendSameArgTypeNode<SendNode
        def collect_candidate_type_regident(context, slf)
          sig = context.to_signature
          same_type(self, @arguments[3], sig, sig, context)
          context
        end
      end

      class SendPNode<SendSameArgTypeNode
        add_special_send_node :p
      end

      class SendSameSelfTypeNode<SendNode
        def collect_candidate_type_regident(context, slf)
          sig = context.to_signature
          same_type(self, @arguments[2], sig, sig, context)
=begin
          p debug_info
          p @func.name
          p @arguments[2].type_list(sig)
          p @arguments[2].class
=end
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

      class SendSortNode<SendSameSelfTypeNode
        add_special_send_node :sort
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
          fadd = OpMemAddress.new(address_of(fname))
          context.start_arg_reg(FUNC_FLOAT_ARG)
          context.start_arg_reg
          asm = context.assembler
          asm.with_retry do
            asm.mov(FUNC_FLOAT_ARG[0], context.ret_reg)
          end
          context.set_reg_content(FUNC_FLOAT_ARG[0].dst_opecode, 
                                  context.ret_node)
          asm.with_retry do
            asm.call_with_arg(fadd, 1)
            asm.sub(SPR, 8)
            asm.fstpl(INDIRECT_SPR)
            asm.pop(XMM0)
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

          @arguments[3].decide_type_once(context.to_signature)
          rtype = @arguments[3].type
          rrtype = rtype.ruby_type
          context = @arguments[3].compile(context)
          context = rtype.gen_unboxing(context)
          compile_main(context)
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

      class RetArraySendNode<RawSendNode
        include AbsArch
        include UnboxedArrayUtil

        def collect_candidate_type_body(context)
          sig = context.to_signature
          tt = RubyType::BaseType.from_ruby_class(Array)
          if context.options[:compile_array_as_uboxed] and
              @element_node_list.size > 1 and 
                @element_node_list[1..-1].all? {|e|
                  e[3]
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
            siz = ((@element_node_list[1..-1].max_by {|a| a[3][0]})[3][0]) + 1
            context = gen_alloca(context, siz)

            context.start_arg_reg(TMPR2)
            asm = context.assembler
            asm.with_retry do
              asm.mov(TMPR2, THEPR)
            end

            @arguments[1..-1].each_with_index do |anode, idx|
              context.start_using_reg(TMPR2)
              context = gen_set_element(context, nil, idx, anode)
              context.end_using_reg(TMPR2)
            end

            asm.with_retry do
              asm.mov(RETR, TMPR2)
            end
            context.end_arg_reg(TMPR2)

            context.ret_reg = RETR
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
