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
          @@special_node_tab[name] = self
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
        end

        def collect_candidate_type_regident(context, slf)
          context
        end

        def collect_info(context)
          traverse_childlen {|rec|
            context = rec.collect_info(context)
          }
          if is_fcall or is_vcall then
            # Call method of same class
            mt = @class_top.method_tab[@func.name]
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
          fnc = nil
          
          case callconv
          when :c_vararg
            context.start_using_reg(TMPR2)
            
            context = gen_make_argv(context) do |context, rarg|
              context.start_using_reg(FUNC_ARG[0])
              context.start_using_reg(FUNC_ARG[1])
              context.start_using_reg(FUNC_ARG[2])
              
              context.cpustack_pushn(3 * AsmType::MACHINE_WORD.size)
              casm = context.assembler
              # Method Select
              # it is legal. use TMPR2 for method select
              # use TMPR3 for store self
              context = @func.compile(context)
              fnc = context.ret_reg
              casm.with_retry do 
                casm.mov(FUNC_ARG[0], rarg.size) # argc
                casm.mov(FUNC_ARG[1], TMPR2)     # argv
                casm.mov(FUNC_ARG[2], TMPR3)     # self
              end
              context.set_reg_content(FUNC_ARG[0], nil)
              context.set_reg_content(FUNC_ARG[1], TMPR2)
              context.set_reg_content(FUNC_ARG[2], context.ret_node)
              
              context = gen_call(context, fnc, 3)
              context.cpustack_popn(3 * AsmType::MACHINE_WORD.size)
              
              context.end_using_reg(FUNC_ARG[2])
              context.end_using_reg(FUNC_ARG[1])
              context.end_using_reg(FUNC_ARG[0])
              context.end_using_reg(TMPR2)
              context.ret_reg = RETR
              context.ret_node = self
              
              decide_type_once(context.to_signature)
              context = @type.to_box.gen_unboxing(context)

              context
            end
            
          when :c_fixarg
            numarg = @arguments.size - 2
            
            numarg.times do |i|
              context.start_using_reg(FUNC_ARG[i])
            end
            context.cpustack_pushn(numarg * AsmType::MACHINE_WORD.size)
            
            argpos = 0
            cursrc = 0
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
                # use TMPR3 for store self
                context = @func.compile(context)
                fnc = context.ret_reg
                casm = context.assembler
                casm.with_retry do 
                  casm.mov(FUNC_ARG[0], TMPR3)
                end
                context.set_reg_content(FUNC_ARG[0], context.ret_node)
              else
                # other arg.
                context = arg.compile(context)
                context.ret_node.decide_type_once(context.to_signature)
                rtype = context.ret_node.type
                context = rtype.gen_boxing(context)
                casm = context.assembler
                casm.with_retry do 
                  casm.mov(FUNC_ARG[argpos], context.ret_reg)
                end
                context.set_reg_content(FUNC_ARG[argpos], context.ret_node)
              end
              argpos = argpos + 1
              cursrc = cursrc + 1
            end
            
            context = gen_call(context, fnc, numarg)
            
            context.cpustack_popn(numarg * AsmType::MACHINE_WORD.size)
            numarg.times do |i|
              context.end_using_reg(FUNC_ARG[numarg - i - 1])
            end
            context.end_using_reg(fnc)

            decide_type_once(context.to_signature)
            context = @type.to_box.gen_unboxing(context)

          when :ytl
            numarg = @arguments.size
            
            numarg.times do |i|
              context.start_using_reg(FUNC_ARG_YTL[i])
            end
            context.cpustack_pushn(numarg * 8)
               
            # push prev env
            casm = context.assembler
            casm.with_retry do 
              casm.mov(FUNC_ARG_YTL[0], BPR)
            end
            context.set_reg_content(FUNC_ARG_YTL[0], BPR)
            
            # block
            # eval block
            # local block

            # compile block with other code space and context
            tcontext = context.dup
            @arguments[1].compile(tcontext)

            casm = context.assembler
            casm.with_retry do 
              entry = @arguments[1].code_space.var_base_immidiate_address
              casm.mov(FUNC_ARG_YTL[1], entry)
            end
            context.set_reg_content(FUNC_ARG_YTL[1], nil)
            
            # other arguments
            @arguments[3..-1].each_with_index do |arg, i|
              context = arg.compile(context)
              casm = context.assembler
              casm.with_retry do 
                casm.mov(FUNC_ARG_YTL[i + 3], context.ret_reg)
              end
              context.set_reg_content(FUNC_ARG_YTL[i + 3], context.ret_node)
            end
            
            # self
            # Method Select
            # it is legal. use TMPR2 for method select
            # use TMPR3 for store self
            context = @func.compile(context)
            fnc = context.ret_reg
            casm = context.assembler
            casm.with_retry do 
              casm.mov(FUNC_ARG_YTL[2], TMPR3)
            end
            context.set_reg_content(FUNC_ARG_YTL[2], @arguments[2])

            context = gen_call(context, fnc, numarg)
            
            context.cpustack_popn(numarg * 8)
            numarg.size.times do |i|
              context.end_using_reg(FUNC_ARG_YTL[numarg - i])
            end
            context.end_using_reg(fnc)
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
            @class_top.method_tab[arguments[4].value] = @new_method
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

      class SendPlusNode<SendNode
        include ArithmeticOperationUtil
        include SendUtil
        add_special_send_node :+

        def initialize(parent, func, arguments, op_flag)
          super
        end

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
          if rtype.is_a?(RubyType::DefaultType0) or
              @class_top.method_tab(rtype.ruby_type)[@func.name] then
            return super(context)
          end

          context.current_method_signature.push signature(context)
          if rtype.ruby_type == Fixnum then
            context = gen_arithmetic_operation(context, :add, TMPR2, TMPR)
          elsif rtype.ruby_type == Float then
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

        def initialize(parent, func, arguments, op_flag)
          super
        end

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
          if rtype.is_a?(RubyType::DefaultType0) or
              @class_top.method_tab(rtype.ruby_type)[@func.name] then
            return super(context)
          end

          context.current_method_signature.push signature(context)
          if rtype.ruby_type == Fixnum then
            context = gen_arithmetic_operation(context, :sub, TMPR2, TMPR)
          elsif rtype.ruby_type == Float then
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

        def initialize(parent, func, arguments, op_flag)
          super
        end

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
          if rtype.is_a?(RubyType::DefaultType0) or
              @class_top.method_tab(rtype.ruby_type)[@func.name] then
            return super(context)
          end

          context.current_method_signature.push signature(context)
          if rtype.ruby_type == Fixnum then
            context = gen_arithmetic_operation(context, :imul, TMPR2, 
                                               TMPR) do |context|
              asm = context.assembler
              asm.with_retry do
                asm.mov(DBLLOR, TMPR2)
                asm.imul(context.ret_reg)
                context.end_using_reg(context.ret_reg)
              end
            end
              
          elsif rtype.ruby_type == Float then
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

        def initialize(parent, func, arguments, op_flag)
          super
        end

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
          if rtype.is_a?(RubyType::DefaultType0) or
              @class_top.method_tab(rtype.ruby_type)[@func.name] then
            return super(context)
          end

          context.current_method_signature.push signature(context)
          if rtype.ruby_type == Fixnum then
            context = gen_arithmetic_operation(context, :imul, TMPR2, 
                                               TMPR) do |context|
              asm = context.assembler
              asm.with_retry do
                asm.mov(DBLLOR, TMPR2)
                asm.cdq
                asm.idiv(context.ret_reg)
                asm.and(TMPR2, TMPR2)
                asm.setnz(TMPR2)
                asm.neg(TMPR2)
                asm.and(TMPR2, DBLLOR)
                asm.setl(TMPR2)
                asm.sub(DBLLOR, TMPR2)
                context.end_using_reg(context.ret_reg)
              end
            end
              
          elsif rtype.ruby_type == Float then
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
          if rtype.ruby_type.is_a?(RubyType::DefaultType0) or
              @class_top.method_tab(rtype.ruby_type)[@func.name] then
            return super(context)
          end

          context.current_method_signature.push signature(context)
          context = gen_eval_self(context)
          if rtype.ruby_type == Fixnum then
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
            @arguments[3].add_type(context.to_signature, fixtype)
            @arguments[2].add_element_node(context.to_signature, self, context)
            key = context.to_signature
            decide_type_once(key)
#            @arguments[2].type = nil
#            @arguments[2].decide_type_once(context.to_signature)
            epare = @arguments[2].element_node_list[0]
            ekey = epare[0]
            enode = epare[1]
            if enode != self then
              same_type(self, enode, key, ekey, context)
              same_type(enode, self, ekey, key, context)
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
