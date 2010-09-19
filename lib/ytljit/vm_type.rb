module YTLJit
  module TypeUtil
    class KlassTree
      def initialize(defkey = [], defval = [])
        @node = KlassTreeNode.new(defkey, defval)
      end

      def add(key, value)
        cnode = @node
        snode = @node
        ocnode = nil
        while cnode
          ocnode = cnode
          if key.zip(cnode.key).all? {|a, b| a == b } then
            return cnode
          end
          
          if key.zip(cnode.key).all? {|a, b| b.is_a?(a.class) } then
            cnode = cnode.same_klass
            if cnode == nil then
              ocnode.same_klass = KlassTreeNode.new(key, value)
              return snode
            else
              snode = cnode
            end
          else
            cnode = cnode.next_klass
            if cnode == nil then
              ocnode.next_klass = KlassTreeNode.new(key, value)
              return snode
            end
          end
        end
      end

      def search(key)
        cnode = @node

        while cnode
          if key.zip(cnode.key).all? {|a, b| a == b } then
            return cnode
          end
          
          if key.zip(cnode.key).all? {|a, b| b.is_a?(a.class) } then
            cnode = cnode.same_klass
          else
            cnode = cnode.next_klass
          end
        end
        
        nil
      end
    end

    class KlassTreeNode
      def initialize(key, value)
        @same_klass = nil
        @next_klass = nil

        @key = key
        @value = value
      end

      attr_accessor :same_klass
      attr_accessor :next_klass
      attr          :key
      attr_accessor :value
    end

    class TypeContainer
      def initialize
        @types_tree = KlassTree.new
      end

      def to_key(context)
        context.current_method_signature.last
      end

      def search_types(key)
        @types_tree.search(key)
      end

      def add_type(type, context)
        key = context.to_key
        tvs = @types_tree.search(key).value
        if tvs then
          tvs.push type
        else
          # inherit types of most similar signature 
          ival = []
          simnode = @types_tree.add(key, ival)
          simnode.value.each do |ele|
            val.push ele
          end

          if ival.all? {|ele| type.class != ele.class} then
            ival.push type
          end
        end
      end

      def type_list(context)
        key = context.to_key
        search_types(key)
      end
    end
  end

  module RubyType
    def self.define_wraped_class(klass, base = RubyTypeBoxed)
      cn = nil

      if klass then
        cn = (klass.name + "Type").to_sym
        newc = nil
        if !const_defined?(cn) then
          supklass = define_wraped_class(klass.superclass)

          newc = Class.new(supklass)
          newc.instance_eval { related_ruby_class klass}
          const_set(cn, newc)
        else
          newc = const_get(cn)
        end

        newc
      else
        base
      end
    end
          
    class BaseType
      @@boxed_klass_tab = {}
      @@unboxed_klass_tab = {}
      @@box_to_unbox_tab = {}
      @@unbox_to_box_tab = {}

      def self.related_ruby_class(klass)
        @@boxed_klass_tab[klass] = self
        unboxslf = Class.new(RubyTypeUnboxed)
        @@unboxed_klass_tab[klass] = unboxslf
        @@box_to_unbox_tab[self] = unboxslf
        @@unbox_to_box_tab[unboxslf] = self
      end

      def self.from_object(obj)
        klass =  @@boxed_klass_tab[obj.class]
        if klass then
          klass.new(obj.class)
        else
          DefaultType0.new(obj.class)
        end
      end

      def self.from_ruby_class(rcls)
        klass =  @@boxed_klass_tab[rcls]
        if klass then
          klass.new(rcls)
        else
          DefaultType0.new(rcls)
        end
      end

      def initialize(rtype)
        @asm_type = Type::MACHINE_WORD
        @ruby_type = rtype
      end

      attr_accessor :asm_type
      attr_accessor :ruby_type
    end

    # Same as VALUE type in MRI
    # Type0 makes you can define "Defalut" class 
    class DefaultType0<BaseType
      def initialize(klass)
        super
      end

      def boxed
        true
      end
    end

    class RubyTypeBoxed<BaseType
      def boxed
        true
      end

      def to_unbox
        @@box_to_unbox_tab[self.class].new(@ruby_type)
      end

      def to_box
        self
      end
    end

    class RubyTypeUnboxed<BaseType
      def boxed
        false
      end

      def to_box
        @@unbox_to_box_tab[self.clsss].new(@ruby_type)
      end

      def to_unbox
        self
      end
    end

    YTLJit::RubyType::define_wraped_class(Fixnum, RubyTypeUnboxed)
    YTLJit::RubyType::define_wraped_class(NilClass,  RubyTypeUnboxed)
    YTLJit::RubyType::define_wraped_class(Float, RubyTypeUnboxed)
  end
end
