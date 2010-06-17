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
          if @func.written_in == :c then
            rec = @func.reciever
            mname = @func.name
            if variable_argument?(rec.method(mname).parameters) then
              casm = context.assembler
              
              # make argv
              rarg = @arguments[2..-1]
              casm.with_retry do
                casm.sub(SPR, rarg.size * Type::MACHINE_WORD.size)
              end

              rarg.each_with_index do |arg, i|
                context = arg.compile(context)
                casm = context.assembler
                dst = OpIndirect.new(SPR, i * Type::MACHINE_WORD.size)
                casm.with_retry do
                  casm.mov(TMPR, context.ret_reg)
                  casm.mov(dst, TMPR)
                end
              end
              
              # adjust stack pointer
              casm.with_retry do
                casm.mov(TMPR2, SPR)
              end

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
              
              casm = context.assembler
              casm.with_retry do 
                casm.call_with_arg(fnc, @arguments.size)
              end
              off = casm.offset
              @var_return_address = casm.output_stream.var_base_address(off)

              casm.with_retry do
                casm.add(SPR, rarg.size * Type::MACHINE_WORD.size)
              end
              context.ret_reg = RETR
              
              @body.compile(context)
              
              return context
            else
              @arguments.each_with_index do |arg, i|
                context = arg.compile(context)
                casm = context.assembler
                casm.with_retry do 
                  casm.mov(FUNC_ARG[i], context.ret_reg)
                end
              end
            end
          else
            @arguments.each_with_index do |arg, i|
              context = arg.compile(context)
              casm = context.assembler
              casm.with_retry do 
                casm.mov(FUNC_ARG_YTL[i], context.ret_reg)
              end
            end
          end
          casm = context.assembler
          casm.with_retry do 
            casm.call_with_arg(fnc, @arguments.size)
          end
          off = casm.offset
          @var_return_address = casm.output_stream.var_base_address(off)
          context.ret_reg = RETR

          @body.compile(context)

          context
        end
      end

      class SendCoreDefineMethod<SendNode
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

      class SendPlus<SendNode
        add_special_send_node :+
        def initialize(parent, func, argument, op_flag)
          super
        end
      end
    end
  end
end
