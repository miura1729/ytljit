require 'ytljit'

class Foo
  def foo
    x = 10
    lambda {|y, z|
      lambda {|c|
        [1, 2][0] = 2
        p y
        p c + y + z + x
        p self
      }
    }.call(1, 3)
  end
end

a = Foo.new
b = a.foo
b.call(2)

Marshal.load(Marshal.dump(b)).call(2)

