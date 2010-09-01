module YTLJit
  module RubyType
    class BaseType
      @@boxed_klass_tab = {}
      @@unboxed_klass_tab = {}
      @@box_to_unbox_tab = {}
      @@unbox_to_box_tab = {}

      def self.related_ruby_class(klass)
        @@boxed_klass_tab[klass] = self
        unboxslf = self.dup.instance_eval {include UnBoxedTypeMixin}
        @@unboxed_klass_tab[klass] = unboxslf
        @@box_to_unbox_tab[self] = unboxslf
        @@unbox_to_box_tab[unboxslf] = self
      end

      def self.from_object(obj)
        klass =  @@boxed_klass_tab[obj.class]
        if klass then
          klass.new
        else
          DefaultType.new
        end
      end

      def self.from_ruby_class(rcls)
        klass =  @@boxed_klass_tab[rcls]
        if klass then
          klass.new
        else
          DefaultType.new
        end
      end

      def initialize
        @asm_type = Type::MACHINE_WORD
      end

      def boxed
        true
      end

      attr_accessor :asm_type
    end

    # Same as VALUE type in MRI
    class DefaultType<BaseType
      def initialize
        super
      end
    end

    module UnBoxedTypeMixin
      def boxed
        false
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

    class FloatType<DefaultType
      related_ruby_class Float

      def initialize
        super
      end
    end
  end
end
