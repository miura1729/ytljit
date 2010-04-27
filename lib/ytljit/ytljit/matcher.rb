# Pattern matcher
# Usage
#     When pattern matched, block is yielded with argument is hash that maps
#    symbol to value.
#
#    mat = Matcher.new
#    mat.pattern([:a, :b]) {|hash|
#       p hash
#    }
#    mat.match([1, 2])
#
#    Output "{:a => 1, :b => 2}"
#
#    [Class_Name, Symbol] is special case.
#    Match when class of corresponding value is Class_Name. And bind
#    Symbol in argument hash of block.
#
#    mat.pattern([:a, [Array, :d]]) {|hash|
#       p hash
#    }
#    mat.match([1, [3, 4, 5]])
#
#   Output "{:a=>1, :d=>[3, 4, 5]}"
#
#
#    You can use multiple patterns
#    When multiple patterns matched execute a block for 1 pattern. But 
#    execution pattern  is undefined.
#
#  mat = Matcher.new
#  mat.pattern([:a, :b]) {|hash|
#    p hash
#  }
#  mat.pattern(:a) {|hash|
#    p hash
#  }
#  mat.pattern([:a, [:b, :d]]) {|hash|
#    p hash
#  }
#  mat.pattern([:a, [Array, :d], :c]) {|hash|
#    p hash
#  }
#  mat.match([1, [2, 3]])  # => {:a=>1, :b=>[2, 3]}
#  mat.match([1, [2, 3], 4]) # => {:a=>1, :d=>[2, 3], :c=>4}
#  mat.match([1, [2, 3], 4, 5]) # => {:a=>[1, [2, 3], 4, 5]}
#

#
class Matcher
  def initialize
    @cache = {}
    @code = nil
    @pattern = []
  end

  def match(src)
    unless @code
      compile
    end
    @src = src
    @code.eval
  end
  
  def pattern(pat, &block)
    unless @code
      @pattern.push [pat, block]
    end
  end
  
  def compile
    info = {}
    @pattern.each do |pat|
      env = {}
      cond = compile_aux(pat[0], [], env, [])[0]
      info[cond] = [env, pat[1]]
    end
    @code = code_gen(info)
  end

  def compile_aux(pat, stack, env, cond)
    status = :normal
    case pat
    when Array
      if pat[0].is_a?(Class) then
        cond.push "(#{get_patref(stack)}.is_a?(#{pat[0]}))"
        env[pat[1]] = "#{get_patref(stack)}"
      else
        cond.push "(#{get_patref(stack)}.is_a?(Array))"
        stack.push 0
        pat.each_with_index do |ele, i|
          stack[-1] = i
          cond, st = compile_aux(ele, stack, env, cond)
          if st == :return then
            stack.pop
            return [cond, status]
          end
        end
        stack[-1] = pat.size
        cond.push "(#{get_patref(stack)} == nil)"
        stack.pop
      end
      
    when Symbol
      patstr = pat.to_s
      if patstr[0] == '_' then
        npat = patstr[1..-1].to_sym
        if env[npat] then
          cond.push "#{get_patref_rest(stack)} == #{env[npat]}"
        else
          env[npat] = get_patref_rest(stack)
        end
        status = :return
      else
        if env[pat] then
          cond.push "(#{get_patref(stack)}.is_a?(Symbol) or #{get_patref(stack)} == #{env[pat]})"
        else
          env[pat] = get_patref(stack).to_s
        end
      end

    else
      cond.push "(#{get_patref(stack)} == #{pat})"
    end

    return [cond, status]
  end

  def get_patref(stack)
    code = "@src"
    stack.each do |n|
      code += "[#{n}]"
    end
    code
  end

  def get_patref_rest(stack)
    code = "@src"
    top = stack.pop
    stack.each do |n|
      code += "[#{n}]"
    end
    code += "[#{top}.. -1]"
    stack.push top
    code
  end

  def code_gen(info)
    ct = {}
    info.each do |carr, val|
      cursor = ct
      carr.each do |cele|
        cursor[cele] ||= {}
        cursor = cursor[cele]
      end
      cursor[nil] = val
    end

    code = <<-EOS
    org_self = self
    ObjectSpace._id2ref(#{self.object_id}).instance_eval do 
      #{cond_gen(ct, 0)} 
    end
EOS
    RubyVM::InstructionSequence.compile(code)
  end

  def cond_gen(tr, level)
    code = ""
    tr.each do |cond, nxt|
      if cond then
        code << "if #{cond} then \n"
        code << cond_gen(nxt, level + 1)
        code << "end\n"
      end
    end
    if tr[nil] then
      code << "#{exec_gen(tr[nil])} \n"
    end
    code
  end

  def exec_gen(para)
    hash = "{"
    para[0].each do |key, value|
      hash << ":#{key} => #{value},"
    end
    hash << "}"
    
    proc = para[1]
    "break ObjectSpace._id2ref(#{proc.object_id}).call(#{hash})"
  end
end

if __FILE__ == $0 then
  mat = Matcher.new
  mat.pattern([:a, :b]) {|hash|
    p hash
  }
  mat.pattern([:a, :_b]) {|hash|
    p hash
  }
  mat.pattern(:a) {|hash|
    p hash
  }
  mat.pattern([:a, [:b, :_c], 1]) {|hash|
    p hash
  }
  mat.pattern([:a, [Array, :d], :c]) {|hash|
    p hash
  }
  mat.match([1, [2, 3]])
  mat.match([1, [2, 3, 4], 4, :a])
  mat.match([1, [2, 3, 4], 1])
  mat.match([1, [2, 3], 4, 5])
end

