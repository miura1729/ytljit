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
          if key == cnode.key then
            return cnode
          end
          
          if key == cnode.key then
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
          if key == cnode.key then
            return cnode
          end

          if key.zip(cnode.key).all? {|a, b| 
              if a then
                atype = a.ruby_type

                if b then
                  btype = b.ruby_type
                  btype.is_a?(atype.class) 
                else
                  nil
                end
              else
                return !b
              end
            } then
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
        tvs = @types_tree.search(key)
        if tvs then
          tvsv = tvs.value
          if !tvsv.include? type then
            tvsv.push type
          end
        else
          # inherit types of most similar signature 
          ival = []
          simnode = @types_tree.add(key, ival)
          simnode.value.each do |ele|
            val.push ele
          end

          if !ival.include? type then
            ival.push type
          end
        end
      end

      def add_node(context)
        key = context.to_key
        # inherit types of most similar signature 
        ival = []
        simnode = @types_tree.add(key, ival)
        simnode.value.each do |ele|
          ival.push ele
        end

        simnode
      end

      def type_list(context)
        key = context.to_key
        res = search_types(key)
        if res == nil then
          res = add_node(context)
        end
        
        res
      end
    end
  end

  module RubyType
    def self.define_wraped_class(klass, base = RubyTypeBoxed)
      cn = nil

      if klass then
        cn = klass.name.to_sym
        basett, boxtt, unboxtt = BaseType.type_tab
        if boxtt[cn] == nil then
          BaseType.related_ruby_class(klass, base)
        end

        boxobj = boxtt[cn]
        unboxobj = unboxtt[cn]
        [boxobj, unboxobj]
      end
    end
          
    class BaseType
      @@base_type_tab = {}
      @@boxed_type_tab = {}
      @@unboxed_type_tab = {}
      @@box_to_unbox_tab = {}
      @@unbox_to_box_tab = {}

      def self.type_tab
        [@@base_type_tab, @@boxed_type_tab, @@unboxed_type_tab]
      end

      def self.related_ruby_class(klass, base)
        boxslf = RubyTypeBoxed.new(klass)
        mixinname = klass.name + "TypeBoxedCodeGen"
        begin
          mixin = VM::TypeCodeGen.const_get(mixinname)
          boxslf.extend mixin
        rescue NameError
        end

        unboxslf = RubyTypeUnboxed.new(klass)
        mixinname = klass.name + "TypeUnboxedCodeGen"
        begin
          mixin = VM::TypeCodeGen.const_get(mixinname)
          unboxslf.extend mixin
        rescue NameError
        end

        @@base_type_tab[klass] = unboxslf
        @@boxed_type_tab[klass] = boxslf
        @@unboxed_type_tab[klass] = unboxslf
        @@box_to_unbox_tab[boxslf] = unboxslf
        @@box_to_unbox_tab[unboxslf] = unboxslf
        @@unbox_to_box_tab[unboxslf] = boxslf
        @@unbox_to_box_tab[boxslf] = boxslf

        [boxslf, unboxslf]
      end

      def self.from_object(obj)
        from_ruby_class(obj.class)
      end

      def self.from_ruby_class(rcls)
        tobj =  @@base_type_tab[rcls]
        if tobj == nil then
          DefaultType0.new
        else
          tobj.instance
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
      def initialize
        super(Object)
      end

      def boxed
        true
      end

      include VM::TypeCodeGen::DefaultTypeCodeGen
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

      include VM::TypeCodeGen::DefaultTypeCodeGen
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

      include VM::TypeCodeGen::DefaultTypeCodeGen
    end

    YTLJit::RubyType::define_wraped_class(Fixnum, RubyTypeUnboxed)
    YTLJit::RubyType::define_wraped_class(NilClass,  RubyTypeUnboxed)
    YTLJit::RubyType::define_wraped_class(Float, RubyTypeUnboxed)
  end
end
