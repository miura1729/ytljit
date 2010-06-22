require 'ytljit'

class Foo
  def foo
    x = 10
    lambda {|y, z|
      lambda {|c|
        c + y + z + x
        p self
      }
    }.call(1, 3)
  end
end

a = Foo.new
b = a.foo
b.call(2)
p b.binding.to_a
p b.to_iseq.to_a
p b.binding.variables

