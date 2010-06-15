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
