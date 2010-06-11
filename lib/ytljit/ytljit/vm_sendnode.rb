module YTLJit
  module VM
    # Expression of VM is a set of Nodes
    module Node

      # Send methodes
      class SendNode<HaveChildlenNode
        @@current_node = nil
        @@special_node_tab = {}
        
        def self.node
          @@current_node
        end

        def self.add_special_send_node(name)
          @@special_node_tab[name] = self
        end

        def self.make_send_node(parent, func, arguments)
          spcl = @@special_node_tab[func.name]
          if spcl then
            spcl.new(parent, func, arguments)
          else
            self.new(parent, func, arguments)
          end
        end

        def initialize(parent, func, arguments)
          super(parent)
          @func = func
          @arguments = arguments
          @var_return_address = nil
          @next_node = @@current_node
          @@current_node = self
        end

        attr_accessor :func
        attr_accessor :arguments
        attr          :var_return_address
        attr          :next_node

        def traverse_childlen
          @arguments.each do |arg|
            yield arg
          end
          yield @func
        end

        def compile(context)
          @arguments.each_with_index do |arg, i|
            context = arg.compile(context)
            casm = context.assembler
            casm.with_retry do 
              casm.mov(FUNC_ARG[i], context.ret_reg)
            end
          end
          context = @func.compile(context)
          fnc = context.ret_reg
          casm = context.assembler
          casm.with_retry do 
            casm.call(fnc)
          end
          off = casm.offset
          @var_return_address = casm.output_stream.var_base_address(off)

          context
        end
      end

      class SendCoreDefineMethod<SendNode
        add_special_send_node :"core#define_method"
        def initialize(parent, func, arguments)
          super
          if arguments[2].is_a?(LiteralNode) then
            parent.parent.method_tab[arguments[2].value] = arguments[3]
          end
        end
      end
    end
  end
end
