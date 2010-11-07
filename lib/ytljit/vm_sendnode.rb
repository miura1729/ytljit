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
        
        def self.node
          @@current_node
        end

        def self.add_special_send_node(name)
          oldcls = @@special_node_tab[name]
          if oldcls == nil or self < oldcls then
            @@special_node_tab[name] = self

          else
            raise "Illigal SendNode #{self} #{name}"
          end
        end

        def self.make_send_node(parent, func, arguments, op_flag)
          spcl = @@special_node_tab[func.name]
          newobj = nil
          if spcl then
            newobj = spcl.new(parent, func, arguments, op_flag)
          else
            newobj = self.new(parent, func, arguments, op_flag)
          end
          func.parent = newobj
          arguments.each do |ele|
            ele.parent = newobj
          end

          newobj
        end

        def initialize(parent, func, arguments, op_flag)
          super(parent)
          @func = func
          @arguments = arguments
          @opt_flag = op_flag
          @var_return_address = nil
          @next_node = @@current_node
          @@current_node = self

          @class_top = search_class_top
          @frame_info = search_frame_info

          @modified_instance_var = nil
          @modified_local_var = [{}]
        end

        attr_accessor :func
        attr_accessor :arguments
        attr          :opt_flag
        attr          :var_return_address
        attr          :next_node
        attr          :class_top
        attr          :modified_local_var
        attr          :modified_instance_var

        def traverse_childlen
          @arguments.each do |arg|
            yield arg
          end
          yield @func
          yield @body
        end

        def collect_candidate_type_regident(context, slf)
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

          @modified_local_var    = context.modified_local_var.dup
          @modified_instance_var = context.modified_instance_var.dup

          @body.collect_info(context)
        end

        def collect_candidate_type(context)
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
          mt = nil
          if is_fcall or is_vcall then
            mt = @func.method_top_node(@class_top, nil)
          else
            @arguments[2].decide_type_once(context.to_signature)
            slf = @arguments[2].type
            if slf.instance_of?(RubyType::DefaultType0) then
              # Chaos

            else
              mt = @func.method_top_node(@class_top, slf)
            end
          end
          
          if mt then
            same_type(self, mt, context.to_signature, signat, context)
            same_type(mt, self, signat, context.to_signature, context)

            context.current_method_signature_node.push @arguments
            mt.yield_node.map do |ynode|
              yargs = ynode.arguments
              ysignat = ynode.signature(context)
              same_type(blknode, ynode, ysignat, signat, context)
              same_type(ynode, blknode, signat, ysignat, context)
            end
            context.current_method_signature_node.pop

            context = mt.collect_candidate_type(context, @arguments, signat)

            context.current_method_signature_node.push @arguments
            mt.yield_node.map do |ynode|
              yargs = ynode.arguments
              ysignat = ynode.signature(context)
              if blknode.is_a?(TopNode) then
                # Have block
                context = blknode.collect_candidate_type(context, 
                                                         yargs, ysignat)
              else
                context = blknode.collect_candidate_type(context)
              end
            end
            context.current_method_signature_node.pop
          else
            context = collect_candidate_type_regident(context, slf)
          end

          @body.collect_candidate_type(context)
        end

        def compile(context)
          context = super(context)

          context.start_using_reg(TMPR2)
          context.start_using_reg(TMPR3)
          callconv = @func.calling_convention(context)
          
          case callconv
          when :c_vararg
            context = compile_c_vararg(context)
            
          when :c_fixarg
            context = compile_c_fixarg(context)

          when :ytl
            context = compile_ytl(context)
          end
          
          decide_type_once(context.to_signature)
          if @type.is_a?(RubyType::RubyTypeUnboxed) and 
              @type.ruby_type == Float then
            context.ret_reg = XMM0
          else
            context.ret_reg = RETR
          end
          context.ret_node = self
          context.end_using_reg(TMPR3)
          context.end_using_reg(TMPR2)
          
          context = @body.compile(context)
          context
        end
      end

      class SendCoreDefineMethodNode<SendNode
        add_special_send_node :"core#define_method"
        def initialize(parent, func, arguments, op_flag)
          super
          @new_method = arguments[5]
          if arguments[4].is_a?(LiteralNode) then
            @new_method.name = arguments[4].value
            @class_top.get_method_tab[arguments[4].value] = @new_method
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

          context
        end
      end

      class SendCoreDefineSigletonMethodNode<SendNode
        add_special_send_node :"core#define_singleton_method"

        def initialize(parent, func, arguments, op_flag)
          super
          @new_method = arguments[5]
          if arguments[4].is_a?(LiteralNode) then
            @new_method.name = arguments[4].value
            @class_top.make_klassclass_node
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
          rrtype = class << @arguments[3].type.ruby_type; self; end
          clsnode = ClassTopNode.get_class_top_node(rrtype)
          clsnode.get_method_tab[@new_method.name] = @new_method

          @body.collect_candidate_type(context)
          context
        end

        def compile(context)
          context = @body.compile(context)
          ocs = context.code_space
          # Allocate new code space in compiling @new_method
          context = @new_method.compile(context)
          context.set_code_space(ocs)

          context
        end
      end

      class SendAllocateNode<SendNode
        add_special_send_node :allocate

        def collect_candidate_type_regident(context, slf)
          slfnode = @arguments[2]
          if slf.ruby_type.is_a?(Class) then
            case slfnode
            when ConstantRefNode
              clstop = slfnode.value_node
              case clstop
              when ClassTopNode
                tt = RubyType::BaseType.from_ruby_class(clstop.klass_object)
                @type_list.add_type(context.to_signature, tt)
                
              else
                raise "Unkown node type in constant #{slfnode.value_node.class}"
              end

            else
              raise "Unkonwn node type #{@arguments[2].class} "
            end
          end
          context
        end
      end

      class SendInitializeNode<SendNode
        add_special_send_node :initialize

        def compile(context)
          context.start_using_reg(TMPR2)
          context.start_using_reg(TMPR3)
          callconv = @func.calling_convention(context)
          
          case callconv
          when :c_vararg
            context = compile_c_vararg(context)
            
          when :c_fixarg
            context = compile_c_fixarg(context)

          when :ytl
            context = compile_ytl(context)
          end

          decide_type_once(context.to_signature)
          asm = context.assembler
          asm.with_retry do
            asm.mov(RETR, TMPR3)
          end
          context.ret_reg = RETR
          context.ret_node = self
          context.end_using_reg(TMPR3)
          context.end_using_reg(TMPR2)
          
          context = @body.compile(context)
          context
        end
      end

      class SendNewNode<SendNode
        add_special_send_node :new

        def initialize(parent, func, arguments, op_flag)
          super
          allocfunc = MethodSelectNode.new(self, :allocate)
          alloc = SendNode.make_send_node(self, allocfunc, arguments[0, 3], 0)
          allocfunc.set_reciever(alloc)
          initfunc = MethodSelectNode.new(self, :initialize)
          initarg = arguments.dup
          initarg[2] = alloc
          init = SendNode.make_send_node(self, initfunc, initarg, op_flag)
          initfunc.set_reciever(init)
          alloc.parent = init
          @initmethod = init
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

          if slf.ruby_type.is_a?(Class) then
            case slfnode
            when ConstantRefNode
              context = @initmethod.collect_candidate_type(context)
              case slfnode.value_node
              when ClassTopNode
                clstop = slfnode.value_node
                tt = RubyType::BaseType.from_ruby_class(clstop.klass_object)
                @type_list.add_type(context.to_signature, tt)
                
              else
                raise "Unkown node type in constant #{slfnode.value_node.class}"
              end

            else
              raise "Unkonwn node type #{@arguments[2].class} "
            end
          end
          context
        end
        
        def compile(context)
          @arguments[2].decide_type_once(context.to_signature)
          rtype = @arguments[2].type
          rrtype = rtype.ruby_type
          if rrtype.is_a?(Class) then
            @initmethod.compile(context)
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
            same_type(@arguments[3], @arguments[2], 
                      context.to_signature, context.to_signature, context)
            same_type(@arguments[2], @arguments[3], 
                      context.to_signature, context.to_signature, context)
            same_type(self, @arguments[2], 
                      context.to_signature, context.to_signature, context)
            same_type(@arguments[2], self, 
                      context.to_signature, context.to_signature, context)
          end

          context
        end

#=begin
        def compile(context)
          @arguments[2].decide_type_once(context.to_signature)
          rtype = @arguments[2].type
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
             @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

          context.current_method_signature.push signature(context)
          if rrtype == Fixnum then
            context = gen_arithmetic_operation(context, :add, TMPR2, TMPR)
          elsif rrtype == Float then
            context = gen_arithmetic_operation(context, :addsd, XMM4, XMM0)
          else
            raise "Unkown method #{rtype.ruby_type}##{@func.name}"
          end
          context.current_method_signature.pop
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
            same_type(@arguments[3], @arguments[2], 
                      context.to_signature, context.to_signature, context)
            same_type(@arguments[2], @arguments[3], 
                      context.to_signature, context.to_signature, context)
            same_type(self, @arguments[2], 
                      context.to_signature, context.to_signature, context)
            same_type(@arguments[2], self, 
                      context.to_signature, context.to_signature, context)
          end

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

          context.current_method_signature.push signature(context)
          if rrtype == Fixnum then
            context = gen_arithmetic_operation(context, :sub, TMPR2, TMPR)
          elsif rrtype == Float then
            context = gen_arithmetic_operation(context, :subsd, XMM4, XMM0)
          else
            raise "Unkown method #{rtype.ruby_type}##{@func.name}"
          end

          context.current_method_signature.pop
          @body.compile(context)
        end
      end

      class SendMultNode<SendNode
        include ArithmeticOperationUtil
        include SendUtil
        add_special_send_node :*

        def collect_candidate_type_regident(context, slf)
          case [slf.ruby_type]
          when [Fixnum], [Float]
            same_type(@arguments[3], @arguments[2], 
                      context.to_signature, context.to_signature, context)
            same_type(@arguments[2], @arguments[3], 
                      context.to_signature, context.to_signature, context)
            same_type(self, @arguments[2], 
                      context.to_signature, context.to_signature, context)
            same_type(@arguments[2], self, 
                      context.to_signature, context.to_signature, context)

          when [String]
            same_type(self, @arguments[2], 
                      context.to_signature, context.to_signature, context)
            same_type(@arguments[2], self, 
                      context.to_signature, context.to_signature, context)
            @arguments[3].add_type(context.to_signature, fixtype)
          end

          context
        end

        def compile(context)
          @arguments[2].type = nil
          @arguments[2].decide_type_once(context.to_signature)
          rtype = @arguments[2].type
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
             @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

          context.current_method_signature.push signature(context)
          if rrtype == Fixnum then
            context = gen_arithmetic_operation(context, :imul, TMPR2, 
                                               TMPR) do |context|
              asm = context.assembler
              asm.with_retry do
                asm.mov(DBLLOR, TMPR2)
                asm.imul(context.ret_reg)
                context.end_using_reg(context.ret_reg)
              end
            end
              
          elsif rrtype == Float then
            context = gen_arithmetic_operation(context, :mulsd, XMM4, XMM0)
          else
            raise "Unkown method #{rtype.ruby_type}##{@func.name}"
          end

          context.current_method_signature.pop
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
            same_type(@arguments[3], @arguments[2], 
                      context.to_signature, context.to_signature, context)
            same_type(@arguments[2], @arguments[3], 
                      context.to_signature, context.to_signature, context)
            same_type(self, @arguments[2], 
                      context.to_signature, context.to_signature, context)
            same_type(@arguments[2], self, 
                      context.to_signature, context.to_signature, context)
          end

          context
        end

        def compile(context)
          @arguments[2].type = nil
          @arguments[2].decide_type_once(context.to_signature)
          rtype = @arguments[2].type
          rrtype = rtype.ruby_type
          if rtype.is_a?(RubyType::DefaultType0) or
              @class_top.search_method_with_super(@func.name, rrtype)[0] then
            return super(context)
          end

          context.current_method_signature.push signature(context)
          if rrtype == Fixnum then
            context = gen_arithmetic_operation(context, :imul, TMPR2, 
                                               TMPR) do |context|
              asm = context.assembler
              asm.with_retry do
                asm.mov(DBLLOR, TMPR2)
                asm.cdq
                asm.idiv(context.ret_reg)
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

          context.current_method_signature.pop
          @body.compile(context)
        end
      end

      class SendCompareNode<SendNode
        include SendUtil
        def collect_candidate_type_regident(context, slf)
          same_type(@arguments[3], @arguments[2], 
                    context.to_signature, context.to_signature, context)
          same_type(@arguments[2], @arguments[3], 
                    context.to_signature, context.to_signature, context)
          tt = RubyType::BaseType.from_ruby_class(true)
          @type_list.add_type(context.to_signature, tt)
          tt = RubyType::BaseType.from_ruby_class(false)
          @type_list.add_type(context.to_signature, tt)

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

          context.current_method_signature.push signature(context)
          context = gen_eval_self(context)
          if rrtype == Fixnum then
            context = compile_compare(context)
          else
            raise "Unkown method #{rtype.ruby_type} #{@func.name}"
          end
          context.current_method_signature.pop
          @body.compile(context)
        end
      end

      class SendGtNode<SendCompareNode
        include CompareOperationUtil
        add_special_send_node :<
        def compile_compare(context)
          context = gen_compare_operation(context , :setg, TMPR2, TMPR)
        end
      end

      class SendGeNode<SendCompareNode
        include CompareOperationUtil
        add_special_send_node :<=
        def compile_compare(context)
          context = gen_compare_operation(context , :setge, TMPR2, TMPR)
        end
      end

      class SendLtNode<SendCompareNode
        include CompareOperationUtil
        add_special_send_node :>
        def compile_compare(context)
          context = gen_compare_operation(context , :setl, TMPR2, TMPR)
        end
      end

      class SendLeNode<SendCompareNode
        include CompareOperationUtil
        add_special_send_node :>=
        def compile_compare(context)
          context = gen_compare_operation(context , :setle, TMPR2, TMPR)
        end
      end

      class SendElementRefNode<SendNode
        include SendUtil
        add_special_send_node :[]
        def collect_candidate_type_regident(context, slf)
          case [slf.ruby_type]
          when [Array]
            fixtype = RubyType::BaseType.from_ruby_class(Fixnum)
            sig = context.to_signature
            @arguments[3].add_type(sig, fixtype)
            @arguments[2].add_element_node(sig, self, context)
            decide_type_once(sig)
            @arguments[2].type = nil
            @arguments[2].decide_type_once(sig)
            epare = @arguments[2].element_node_list[0]
            esig = epare[0]
            enode = epare[1]
            if enode != self then
              same_type(self, enode, sig, esig, context)
              same_type(enode, self, esig, sig, context)
            end

          when [Hash]
            @arguments[2].add_element_node(context.to_signature, self, context)


          else
            raise "Unkown type #{slf.ruby_type} in :[]"
          end

          context
        end
      end

      class SendElementAssignNode<SendNode
        include SendUtil
        add_special_send_node :[]=
        def collect_candidate_type_regident(context, slf)
          case [slf.ruby_type]
          when [Array]
            fixtype = RubyType::BaseType.from_ruby_class(Fixnum)
            sig = context.to_signature
            val = @arguments[4]
            @arguments[3].add_type(sig, fixtype)
            @arguments[2].add_element_node(sig, val, context)
            decide_type_once(sig)
            @arguments[2].type = nil
            @arguments[2].decide_type_once(sig)
            epare = @arguments[2].element_node_list[0]
            esig = epare[0]
            enode = epare[1]
            if enode != self then
              same_type(self, enode, sig, esig, context)
              same_type(enode, self, esig, sig, context)
            end

          when [Hash]
            @arguments[2].add_element_node(context.to_signature, self, context)
          end

          context
        end
      end
    end
  end
end
