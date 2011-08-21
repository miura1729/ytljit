class Proc
  @@iseq_cache = {}
  
  def self._alloc
    Proc.new {}
  end

  def _dump_data
    orgiseq = self.to_iseq
    piseq = @@iseq_cache[orgiseq]
    if !piseq then
      piseq = @@iseq_cache[orgiseq] = patch_iseq(orgiseq.to_a)
    end
      
    [piseq, self.binding.to_a]
  end

  def _load_data(obj)
    iseq, env = obj
    slf = env[0][0]
    $_proc_para = [env, slf]
    prc = lambda {
      $_proc_para[1].instance_eval {
        lambda {|env|
          _lambda_replace
        }
      }.call($_proc_para[0].map {|ele| ele.reverse})
    }
    
    prc2 =  VMLib::InstSeqTree.new(nil, prc.to_iseq.to_a)
    iv = VMLib::InstSeqTree.new(nil, prc2.body[7][3])
    lam = VMLib::InstSeqTree.new(nil, iv.body[5][3])
    lam.body[4][1] = :lambda
    lam.body[4][3] = iseq
    
    prc2.header['type'] = :top
      
    self.copy(ISeq.load(prc2.to_a).eval)
  end

  def patch_iseq(iseq, dbase = 0)
    rbody = []
    iseq2 = VMLib::InstSeqTree.new(nil, iseq)
    
    iseq2.body.each do |ele|
      rbody.push ele
      if ele.is_a?(Array) then
        case ele[0]
        when :send
          if ele[3] then
            ele[3] = patch_iseq(VMLib::InstSeqTree.new(iseq, ele[3]), dbase + 1)
          end
                       
        when :getdynamic
          off = ele[1]
          dep = ele[2]
          if dep > dbase then
            rbody.pop
            rbody.push [:getdynamic, 3, 1 + dbase]
            rbody.push [:putobject, dep - 1 - dbase]
            rbody.push [:opt_aref, 0]
            rbody.push [:putobject, off]
            rbody.push [:opt_aref, 0]
          end
          
        when :setdynamic
          off = ele[1]
          dep = ele[2]
          if dep > dbase then
            rbody.pop
            rbody.push [:getdynamic, 3, 1 + dbase]
            rbody.push [:putobject, dep - 1 - dbase]
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
          rbody.push [:getdynamic, 2, 1 + dbase]
          rbody.push [:dup]
          rbody.push [:opt_length]
          rbody.push [:putobject, 1]
          rbody.push [:opt_sub]
          rbody.push [:putobject, dbase]
          rbody.push [:opt_add]
          rbody.push [:opt_aref, 0]
          rbody.push [:putobject, off]
          rbody.push [:opt_aref, 0]
          
        when :setlocal
          off = ele[1]
          rbody.pop 
          rbody.push [:getdynamic, 2, 1 + dbase]
          rbody.push [:dup]
          rbody.push [:opt_length]
          rbody.push [:putobject, 1]
          rbody.push [:opt_sub]
          rbody.push [:putobject, dbase]
          rbody.push [:opt_add]
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

module YTLJit
  class CodeSpace
    def _dump_data
      [@refer_operands, current_pos, code]
    end

    def _load_data(obj)
      self[0] = obj.pop
      current_pos = obj.pop
      @org_base_address = base_address
      @refer_operands = obj.pop
    end
  end

  module Runtime
    class Arena
      def _dump_data
        []
      end
      
      def _load_data(obj)
      end
    end
  end
end
