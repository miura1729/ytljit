module YTLJit
  module Runtime
    class TypedDataArena
      def initialize(type, arena, origin)
        @type = type
        @arena = arena
        @origin = origin
      end

      def [](*arg)
        TypedDataArena.new(@type[*arg], @arena, @origin)
      end

      def ref
        case @type
        when AsmType::Scalar, AsmType::Pointer, AsmType::Array
          @arena[@origin]
          
        when AsmType::StructMember, AsmType::PointedData
          @arena[@origin + @type.offset]

        end
      end

      def ref=(val)
        case @type
        when AsmType::Scalar, AsmType::Pointer, AsmType::Array
          @arena[@origin] = val
          
        when AsmType::StructMember, AsmType::PointedData
          @arena[@origin + @type.offset] = val

        end
      end
    end
  end
end
