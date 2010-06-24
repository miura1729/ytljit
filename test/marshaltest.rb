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

class Proc
  def self._alloc
    Proc.new {}
  end

  def _dump_data
    [patch_iseq(self.to_iseq.to_a), self.binding.to_a]
  end

  def _load_data(obj)
    iseq, env = obj
    slf = env[0][0]
    $foo = [env, slf]
    prc = lambda {
      $foo[1].instance_eval {
        lambda {|env|
          _lambda_replace
        }
      }.call($foo[0].map {|ele| ele.reverse})
    }
    
    prc2 =  VMLib::InstSeqTree.new(nil, prc.to_iseq.to_a)
    iv = VMLib::InstSeqTree.new(nil, prc2.body[7][3])
    lam = VMLib::InstSeqTree.new(nil, iv.body[5][3])
    lam.body[4][1] = :lambda
    lam.body[4][3] = iseq
    
    prc2.header['type'] = :top
      
    self.copy(ISeq.load(prc2.to_a).eval)
  end

  def patch_iseq(iseq)
    rbody = []
    iseq2 = VMLib::InstSeqTree.new(nil, iseq)
    
    iseq2.body.each do |ele|
      rbody.push ele
      if ele.is_a?(Array) then
        case ele[0]
        when :getdynamic
          off = ele[1]
          dep = ele[2]
          if dep > 0 then
            rbody.pop
            rbody.push [:getdynamic, 3, 1]
            rbody.push [:putobject, dep - 1]
            rbody.push [:opt_aref, 0]
            rbody.push [:putobject, off]
            rbody.push [:opt_aref, 0]
          end
          
        when :setdynamic
          off = ele[1]
          dep = ele[2]
          if dep > 0 then
            rbody.pop
            rbody.push [:getdynamic, 3, 1]
            rbody.push [:putobject, dep - 1]
            rbody.push [:opt_aref, 0]
            rbody.push [:putobject, off]
            rbody.push [:topn, 2]
            rbody.push [:send, :[]=, 2, nil, 0, 0]
            rbody.push [:swap]
            rbody.push [:pop]
          end
          
        when :getlocal
          off = ele[1]
          rbody.pop 
          rbody.push [:getdynamic, 2, 1]
          rbody.push [:dup]
          rbody.push [:opt_length]
          rbody.push [:putobject, 1]
          rbody.push [:opt_sub]
          rbody.push [:opt_aref, 0]
          rbody.push [:putobject, off]
          rbody.push [:opt_aref, 0]
          
        when :setlocal
          off = ele[1]
          rbody.pop 
          rbody.push [:getdynamic, 2, 1]
          rbody.push [:dup]
          rbody.push [:opt_length]
          rbody.push [:putobject, 1]
          rbody.push [:opt_sub]
          rbody.push [:opt_aref, 0]
          rbody.push [:putobject, off]
          rbody.push [:topn, 2]
          rbody.push [:send, :[]=, 2, nil, 0, 0]
          rbody.push [:swap]
          rbody.push [:pop]
        end
      end
    end
    
    iseq2.body = rbody
    iseq2.to_a
  end
end

a = Foo.new
b = a.foo
b.call(2)

Marshal.load(Marshal.dump(b)).call(2)

