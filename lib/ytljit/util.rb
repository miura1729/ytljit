class Object
  def address
    case self
    when Symbol
      case $ruby_platform
      when /x86_64/
        ((((__id__ >> 1) - 4) / 10) << 8) | 0xe
      when /i.86/
        ((((__id__ >> 1) - 4) / 5) << 8) | 0xe
      end
      
    when TrueClass, FalseClass
      __id__

    when NilClass
      4

    else
      __id__ << 1

    end
  end
end

module YTLJit
  def variable_argument?(para)
    para.any? {|item|
      item[0] != :req
    }
  end
  module_function :variable_argument?

  def unboxing(value)
    if value & 1 then
      # fixnum
      value >> 1
    elsif value == 4
      nil
    elsif value == 2
      true
    elsif value == 0
      false
    else
      value
    end
  end

  def boxing
    self
  end

  # Singleton class can't be marshaled.
  # So this class wrap to marshal singleton class
  class ClassClassWrapper
    @@instance_tab = {}

    def self.instance(clsobj)
      ins = @@instance_tab[clsobj] 
      if ins == nil then
        ins = ClassClassWrapper.new(clsobj)
        @@instance_tab[clsobj] = ins
      end

      ins
    end

    def initialize(clsobj)
      @klass_object = clsobj
      @value = nil
    end
    
    def value
      if @value then
        @value
      else
        @value = class << @klass_object; self; end
        @value
      end
    end
    
    def name
      value.name
    end
    
    def ancestors
      value.ancestors
    end
    
    def marshal_dump
      [@klass_object]
    end
    
    def marshal_load(obj)
      @klass_object = obj
      @value = nil
    end

    def superclass
      sup = value.superclass
      ins = @@instance_tab[sup]
      if ins then
        ins
      else
        sup
      end
    end
  end
end

class Fixnum
  def boxing
    (self << 1) + 1
  end
end

class Float
  def unboxing
    [self].pack('d').unpack('q')[0]
  end
end


