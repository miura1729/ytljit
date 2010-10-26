module YTLJit
  module Runtime
    class Arena
      def initialize
        @using = 0
      end

      attr_accessor :using
    end

    class TypedDataArena
      def initialize(type, arena, origin)
        @type = type
        @arena = arena
        @origin = origin
      end

      def [](*arg)
        TypedDataArena.new(@type[*arg], @arena, @origin)
      end

      def cast(otype)
        TypedDataArena.new(otype, @arena, @origin)
      end

      def address
        case @type
        when AsmType::Scalar, 
             AsmType::Pointer, 
             AsmType::Array, 
             AsmType::Struct
          @arena.address + @origin
          
        when AsmType::StructMember, AsmType::PointedData
          @arena.address + @origin + @type.offset

        end
      end

      def ref
        case @type
        when AsmType::Scalar, AsmType::Pointer, AsmType::Array
          @arena[@origin]
          
        when AsmType::StructMember, AsmType::PointedData
          @arena[@origin + @type.offset / AsmType::MACHINE_WORD.size]

        end
      end

      def ref=(val)
        case @type
        when AsmType::Scalar, AsmType::Pointer, AsmType::Array
          @arena[@origin] = val
          
        when AsmType::StructMember, AsmType::PointedData
          @arena[@origin + @type.offset / AsmType::MACHINE_WORD.size] = val

        end
      end
    end
  end
end
