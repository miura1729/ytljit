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

