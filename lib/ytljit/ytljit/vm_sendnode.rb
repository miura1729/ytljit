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
        include UtilCodeGen
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
          @op_flag = op_flag
          @var_return_address = nil
          @next_node = @@current_node
          @@current_node = self

          @class_top = search_class_top
        end

        attr_accessor :func
        attr_accessor :arguments
        attr          :op_flag
        attr          :var_return_address
        attr          :next_node
        attr          :class_top

        def traverse_childlen
          @arguments.each do |arg|
            yield arg
          end
          yield @func
        end

        def compile(context)
          context = super(context)
          context = @func.compile(context)
          fnc = context.ret_reg
          case @func.written_in
          when :c_vararg
            context = gen_make_argv(context) do |context, rarg|
              context.start_using_reg(FUNC_ARG[0])
              context.start_using_reg(FUNC_ARG[1])
              context.start_using_reg(FUNC_ARG[2])

              casm = context.assembler
              casm.with_retry do 
                casm.mov(FUNC_ARG[0], rarg.size) # argc
                casm.mov(FUNC_ARG[1], TMPR2)     # argv
              end
              
              # eval self
              context = @arguments[0].compile(context)
              casm = context.assembler
              casm.with_retry do 
                casm.mov(FUNC_ARG[2], context.ret_reg)
              end
              
              context = gen_call(context, fnc)

              context.start_using_reg(FUNC_ARG[2])
              context.start_using_reg(FUNC_ARG[1])
              context.start_using_reg(FUNC_ARG[0])
              context.end_using_reg(context.ret_reg)
              
              context
            end

          when :c_fixarg
            numarg = @arguments.size
            numarg.times do |i|
              context.start_using_reg(FUNC_ARG[i])
            end

            @arguments.each_with_index do |arg, i|
              context = arg.compile(context)
              casm = context.assembler
              casm.with_retry do 
                casm.mov(FUNC_ARG[i], context.ret_reg)
              end
              context.end_using_reg(context.ret_reg)
            end

            context = gen_call(context, fnc)

            numarg.size.times do |i|
              context.start_using_reg(FUNC_ARG[numarg - i])
            end
            context.end_using_reg(fnc)

          when :ytl
            numarg = @arguments.size
            numarg.times do |i|
              context.start_using_reg(FUNC_ARG_YTL[i])
            end
              
            @arguments.each_with_index do |arg, i|
              context = arg.compile(context)
              casm = context.assembler
              casm.with_retry do 
                casm.mov(FUNC_ARG_YTL[i], context.ret_reg)
              end
              context.end_using_reg(context.ret_reg)
            end

            context = gen_call(context, fnc)

            numarg.size.times do |i|
              context.start_using_reg(FUNC_ARG_YTL[numarg - i])
            end
            context.end_using_reg(fnc)
          end
          
          context.ret_reg = RETR

          context = @body.compile(context)

          context
        end
      end

      class SendCoreDefineMethodNode<SendNode
        add_special_send_node :"core#define_method"
        def initialize(parent, func, arguments, op_flag)
          super
          @new_method = arguments[4]
          if arguments[3].is_a?(LiteralNode) then
            @class_top.method_tab[arguments[3].value] = arguments[4]
          end
        end

        def compile(context)
          context = @body.compile(context)
          context = @new_method.compile(context)
          context.code_space.disassemble

          context
        end
      end

      class SendPlusNode<SendNode
        add_special_send_node :+
        def initialize(parent, func, arguments, op_flag)
          super
        end

        def compile(context)

          # eval 1st arg(self)
          slfnode = @arguments[0]
          context = slfnode.compile(context)
          if slfnode.type.boxed then
            slfreg = context.ret_reg
            context = gen_unboxing(context, slfnode)
            context.end_using_reg(slfreg)
          end

          context.start_using_reg(TMPR2)
          asm = context.assembler
          asm.with_retry do
            asm.mov(TMPR2, context.ret_reg)
          end
          context.end_using_reg(context.ret_reg)

          # @argunemnts[1] is block
          # eval 2nd arguments and added
          aele = @arguments[2]
          context = aele.compile(context)
          if aele.type.boxed then
            slfreg = context.ret_reg
            context = gen_unboxing(context, aele)
            context.end_using_reg(slfreg)
          end

          asm = context.assembler
          asm.with_retry do
            asm.add(TMPR2, context.ret_reg)
          end
          context.end_using_reg(context.ret_reg)

          context.ret_reg = TMPR2
          if type.boxed then
            context = gen_boxing(context, self)
            if context.ret_reg != TMPR2 then
              context.end_using_reg(TMPR2)
            end
          end
            
          context
        end
      end
    end
  end
end
