class Object
  def address
    case self
    when Symbol
      (__id__ >> 1) << 2
      
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

