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
          @modified_local_var = nil
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

          context
        end

        def collect_candidate_type(context)
          traverse_childlen {|rec|
            context = rec.collect_candidate_type(context)
          }
          mt = nil
          if is_fcall or is_vcall then
            mt = @class_top.method_tab[@func.name]
          else
            @arguments[2].decide_type_once(context)
            slf = @arguments[2].type
            mt = @class_top.method_tab[slf.ruby_type.name]
          end
          
          if mt then
            same_type(self, mt, context)
            signode = []
            @arguments.each do |arg|
              signode.push arg
            end
            context = mt.collect_candidate_type(context, signode)
          end

          @body.collect_candidate_type(context)
        end

        def signature(context)
          res = []
          @arguments.each do |ele|
            ele.decide_type_once(context)
            res.push ele.type
          end

          res
        end

        def compile(context)
          context = super(context)
          # it is legal. TMPR2 uses in method select
          context.start_using_reg(TMPR2)
          context.set_reg_content(TMPR2, :nil)
          context = @func.compile(context)
          fnc = context.ret_reg
          case @func.written_in
          when :c_vararg
            context.start_using_reg(RETR)

            context = gen_make_argv(context) do |context, rarg|
              context.start_using_reg(FUNC_ARG[0])
              context.start_using_reg(FUNC_ARG[1])
              context.start_using_reg(FUNC_ARG[2])

              context.cpustack_pushn(3 * Type::MACHINE_WORD.size)
              casm = context.assembler
              casm.with_retry do 
                casm.mov(FUNC_ARG[0], rarg.size) # argc
                casm.mov(FUNC_ARG[1], TMPR2)     # argv
              end
              context.set_reg_content(FUNC_ARG[0], nil)
              context.set_reg_content(FUNC_ARG[1], TMPR2)
              
              # eval self
              context = @arguments[2].compile(context)
              casm = context.assembler
              casm.with_retry do 
                casm.mov(FUNC_ARG[2], context.ret_reg)
              end
              context.set_reg_content(FUNC_ARG[1], context.ret_node)
              
              context = gen_call(context, fnc, 3)

              context.cpustack_popn(3 * Type::MACHINE_WORD.size)
              context.end_using_reg(FUNC_ARG[2])
              context.end_using_reg(FUNC_ARG[1])
              context.end_using_reg(FUNC_ARG[0])
              
              context
            end

          when :c_fixarg
            numarg = @arguments.size - 2

            context.start_using_reg(RETR)
            numarg.times do |i|
              context.start_using_reg(FUNC_ARG[i])
            end
            context.cpustack_pushn(numarg * Type::MACHINE_WORD.size)

            argpos = 0
            cursrc = 0
            @arguments.each do |arg|
              # skip prevenv and block_argument
              if cursrc < 2 then
                cursrc = cursrc + 1
                next
              end

              context = arg.compile(context)
              context.ret_node.decide_type_once(context)
              rtype = context.ret_node.type
              context = rtype.gen_boxing(context)
              casm = context.assembler
              casm.with_retry do 
                casm.mov(FUNC_ARG[argpos], context.ret_reg)
              end
              context.set_reg_content(FUNC_ARG[argpos], context.ret_node)
              context.end_using_reg(context.ret_reg)
              argpos = argpos + 1
              cursrc = cursrc + 1
            end

            context = gen_call(context, fnc, numarg)

            context.cpustack_popn(numarg * Type::MACHINE_WORD.size)
            numarg.times do |i|
              context.end_using_reg(FUNC_ARG[numarg - i - 1])
            end
            context.end_using_reg(fnc)

          when :ytl
            numarg = @arguments.size

            context.start_using_reg(RETR)
            numarg.times do |i|
              context.start_using_reg(FUNC_ARG_YTL[i])
            end
            context.cpustack_pushn(numarg * 8)

            # push prev env
            casm = context.assembler
            casm.with_retry do 
              casm.mov(FUNC_ARG_YTL[0], BPR)
            end
            context.set_reg_content(FUNC_ARG_YTL[0], nil)

            # block
            context = @arguments[1].compile(context)
            casm = context.assembler
            casm.with_retry do 
              entry = @arguments[1].code_space.var_base_address.to_immidiate
              casm.mov(FUNC_ARG_YTL[1], entry)
            end
            context.set_reg_content(FUNC_ARG_YTL[1], nil)
            context.end_using_reg(context.ret_reg)

            # self
            context = @arguments[2].compile(context)
            casm = context.assembler
            casm.with_retry do 
              casm.mov(FUNC_ARG_YTL[2], context.ret_reg)
            end
            context.set_reg_content(FUNC_ARG_YTL[0], context.ret_node)
            context.end_using_reg(context.ret_reg)

            # other arguments
            @arguments[3..-1].each_with_index do |arg, i|
              context = arg.compile(context)
              casm = context.assembler
              casm.with_retry do 
                casm.mov(FUNC_ARG_YTL[i + 3], context.ret_reg)
              end
              context.set_reg_content(FUNC_ARG_YTL[i + 1], context.ret_node)
              context.end_using_reg(context.ret_reg)
            end

            context = gen_call(context, fnc, numarg)

            context.cpustack_popn(numarg * 8)
            numarg.size.times do |i|
              context.end_using_reg(FUNC_ARG_YTL[numarg - i])
            end
            context.end_using_reg(fnc)
          end
          
          context.ret_node = self
          context.ret_reg = RETR

          context.end_using_reg(TMPR2)
          context = @body.compile(context)
        end
      end

      class SendCoreDefineMethodNode<SendNode
        add_special_send_node :"core#define_method"
        def initialize(parent, func, arguments, op_flag)
          super
          @new_method = arguments[5]
          if arguments[4].is_a?(LiteralNode) then
            @class_top.method_tab[arguments[4].value] = arguments[5]
          end
        end

        def traverse_childlen
          yield @body
          yield @new_method
        end

        def collect_candidate_type(context)
          # type inference of @new method execute when "send" instruction.
          @body.collect_candidate_type(context)
        end

        def compile(context)
          context = @body.compile(context)
          ocs = context.code_space
          # Allocate new code space in compiling @new_method
          context = @new_method.compile(context)
          context.add_code_space(ocs)

          context
        end
      end

      class SendPlusNode<SendNode
        add_special_send_node :+

        def initialize(parent, func, arguments, op_flag)
          super
        end

        def collect_candidate_type(context)
          traverse_childlen {|rec|
            context = rec.collect_candidate_type(context)
          }
          mt = nil
          @arguments[2].decide_type_once(context)
          slf = @arguments[2].type

          if slf.instance_of?(RubyType::DefaultType0) then
            # Chaos
            
          else
            mt = @class_top.method_tab[slf.ruby_type.name]
            if mt then
              # for redefined method
              same_type(self, mt, context)
              signode = []
              @arguments.each do |arg|
                signode.push arg
              end
              context = mt.collect_candidate_type(context, signode)
            else
              # regident method
              case [slf.ruby_type]
              when [Fixnum], [Float], [String]
                same_type(@arguments[3], @arguments[2], context)
                same_type(self, @arguments[2], context)
              end
            end
          end

          @body.collect_candidate_type(context)
        end

        def compile(context)
          context.current_method_signature.push signature(context)

          # eval 1st arg(self)
          slfnode = @arguments[2]
          context.start_using_reg(TMPR2)
          context = slfnode.compile(context)

          context.ret_node.decide_type_once(context)
          rtype = context.ret_node.type
          slfreg = context.ret_reg

          context = rtype.gen_unboxing(context)
          if slfreg != context.ret_reg then
            context.end_using_reg(slfreg)
          end

          asm = context.assembler
          asm.with_retry do
            asm.mov(TMPR2, context.ret_reg)
          end
          context.set_reg_content(TMPR2, context.ret_node)
          context.end_using_reg(context.ret_reg)

          # @argunemnts[1] is block
          # @argunemnts[2] is self
          # eval 2nd arguments and added
          aele = @arguments[3]
          context = aele.compile(context)
          context.ret_node.decide_type_once(context)
          rtype = context.ret_node.type
          slfreg = context.ret_reg
          context = rtype.gen_unboxing(context)
          if context.ret_reg != slfreg then
            context.end_using_reg(slfreg)
          end

          asm = context.assembler
          asm.with_retry do
            asm.add(TMPR2, context.ret_reg)
          end
          context.set_reg_content(TMPR2, self)

          context.end_using_reg(context.ret_reg)
          asm.with_retry do
            asm.mov(TMPR, TMPR2)
          end
          context.end_using_reg(TMPR2)

          context.set_reg_content(TMPR, self)
          context.ret_node = self
          context.ret_reg = TMPR

          decide_type_once(context)
          if type.boxed then
            context = type.gen_boxing(context)
          end

          context.current_method_signature.pop
          context
        end
      end
    end
  end
end
