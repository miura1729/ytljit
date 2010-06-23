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
iseq = b.to_iseq.to_a

env = b.binding.to_a
slf = env[0][0]
p env
$foo = [env, slf]
prc = lambda {
  $foo[1].instance_eval {
    lambda {|env|
          _lambda_replace
    }
  }.call($foo[0])
}

prc2 =  VMLib::InstSeqTree.new(nil, prc.to_iseq.to_a)
iv = VMLib::InstSeqTree.new(nil, prc2.body[7][3])
lam = VMLib::InstSeqTree.new(nil, iv.body[5][3])
lam.body[4][1] = :lambda
lam.body[4][3] = iseq

prc2.header['type'] = :top
p ISeq.load(prc2.to_a).eval.call(3)
