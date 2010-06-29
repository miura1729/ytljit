module YTLJit
  module RubyType
    class BaseType

      @@klass_tab = {}
      def self.related_ruby_class(klass)
        @@klass_tab[klass] = self
      end

      def self.from_object(obj)
        klass =  @@klass_tab[obj.class]
        if klass then
          klass.new
        else
          DefaultType.new
        end
      end

      def self.from_ruby_class(rcls)
        klass =  @@klass_tab[rcls]
        if klass then
          klass.new
        else
          DefaultType.new
        end
      end

      def initialize
        @boxed = true
        @asm_type = Type::MACHINE_WORD
      end

      attr_accessor :boxed
      attr_accessor :asm_type
    end

    # Same as VALUE type in MRI
    class DefaultType<BaseType
      def initialize
        super
      end
    end

    class FixnumType<DefaultType
      related_ruby_class Fixnum

      def initialize
        super
      end
    end

    class NilClassType<DefaultType
      related_ruby_class NilClass

      def initialize
        super
      end
    end
  end
end
