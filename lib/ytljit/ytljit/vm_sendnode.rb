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

          clstop = parent
          while !clstop.is_a?(ClassTopNode)
            clstop = clstop.parent
          end
          @class_top = clstop
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
          context = @func.compile(context)
          fnc = context.ret_reg
          case @func.written_in
          when :c_vararg
            context = gen_make_argv(context) do |context, rarg|
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
            end

          when :c_fixarg
            @arguments.each_with_index do |arg, i|
              context = arg.compile(context)
              casm = context.assembler
              casm.with_retry do 
                casm.mov(FUNC_ARG[i], context.ret_reg)
              end
            end

            context = gen_call(context, fnc)

          when :ytl
            @arguments.each_with_index do |arg, i|
              context = arg.compile(context)
              casm = context.assembler
              casm.with_retry do 
                casm.mov(FUNC_ARG_YTL[i], context.ret_reg)
              end
            end

            context = gen_call(context, fnc)
          end
          
          context.ret_reg = RETR

          @body.compile(context)

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
        def initialize(parent, func, argument, op_flag)
          super
        end

        def compile(context)
          p "foo hellow plus"
          context
        end
      end
    end
  end
end
