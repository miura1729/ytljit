require 'ytljit'
require 'pp'

class Foo
  def foo
    x = 10
    lambda {|y, z|
      lambda {|c|
        [1, 2][0] = 2
        p y
        p self
        lambda {
          a = 1
          p c + y + z + x + a
        }.call
      }
    }.call(1, 3)
  end
end

a = Foo.new
b = a.foo
b.call(2)

b = Marshal.load(Marshal.dump(b))
b.call(2)
pp b.to_iseq.to_a
