# require 'lib/ytljit/ytljit.rb'

#include YTLJit

class State
  @@num = 0
  @@states = []

  def self.states
    @@states
  end

  def initialize()
    @id = @@num
    @@states.push self
    @@num += 1
    @transfer = {}
    @transfer[nil] = []
    @isend = false
  end

  def reset
    @transfer = {}
    @transfer[nil] = []
  end

  def clone
    no = State.new
    no.transfer = @transfer.clone
    no.isend = @isend
    no
  end

  attr :id
  attr_accessor :transfer
  attr_accessor :isend

  def add_edge(c, to)
    trans = @transfer[c]
    if c and trans then
      ns = State.new
      @transfer[nil].push ns
      trans = ns.transfer[c] = []
    elsif trans == nil then
      trans = @transfer[c] = []
    end
    trans.push to

  end

  def epsilon_nodes(res)
    if res.include?(self) then
      return res
    end
    res.push self
    @transfer[nil].each do |st|
      res = st.epsilon_nodes(res)
      res.push st if res.include?(st)
    end
    res
  end

  def collect_edge(nodes)
    trans = {}
    nodes.each do |st|
      st.transfer.each do |c, st2|
        if c then
          trans[c] ||= []
          trans[c] += st2
        end
      end
    end
    trans.each do |c, nodes|
      if nodes.size > 1 then
        nodes.each_cons(2) do |e0, e1|
          e0.add_edge(nil, e1)
        end
        trans[c] = [nodes[0]]
      end
    end
    trans[nil] = []
    trans
  end

  def translate_dfa
    enodes = epsilon_nodes([])
    @isend = enodes.any? {|e| e.isend}
    @transfer = collect_edge(enodes)
  end

  def inspect
    res = "#{@id}\n"
    @transfer.each do |c, st|
      st.each do |ele|
        res += "  #{c} -> #{ele.id} #{"  END" if @isend}\n"
      end
    end

    res
  end
end

def parse(regstr)
  parse_aux(regstr, 0, 0)
end

def parse_letter(curstate, c)
  newstate = State.new
#  curstate.add_edge(c, newstate)
  newstate
end

def parse_aux(regstr, cp, nest)
  start_state = end_state = State.new
  s0 = State.new
  start_state.add_edge(nil, s0)
  s1 = s0
  s2 = s1
  orxst = nil
  while cp < regstr.size do
    c = regstr[cp]
    case c
    when '\\'
      cp += 1
      if orxst then
        s2 = orxst
        orxst = nil
      else
        s2 = State.new
      end
      s1.add_edge(regstr[cp], s2)
      s0 = s1
      s1 = s2

    when '('
      s0 = s1
      s1, s2, cp = parse_aux(regstr, cp + 1, nest + 1)
      s0.add_edge(nil, s1)

    when ')'
      if nest > 0 then
        return [start_state, s1, cp]
      end

      raise "Illigal \')\'"

    when '*'
      ns0 = s0.clone
      s0.reset
      n1 = s0
      s1 = ns0
      n2 = State.new
      n1.add_edge(nil, s1)
      s2.add_edge(nil, n2)
      s2.add_edge(nil, s1)
      n1.add_edge(nil, n2)
      s0 = s1
      s1 = n2

    when '|'
      s1 = s0
      orxst = s2

    else
      if orxst then
        s2 = orxst
        orxst = nil
      else
        s2 = State.new
      end
      s1.add_edge(c, s2)
      s0 = s1
      s1 = s2
    end
    
    cp += 1
  end
  end_state = s1
  s1.isend = true

  [start_state, end_state, cp]
end

#s, e = parse("cb*ab")
#s, e = parse("(ab)(abc)*(ab)")
#s, e = parse("c(abc)*ab")
s, e = parse("c(abc)*a|b|c")
State.states.each do |s|
  s.translate_dfa
end

State.states.each do |s|
  p s
end

def raw_str(str)
  eax = OpEAX.instance
  esp = OpESP.instance

  asm = Assembler.new(cs = CodeSpace.new)
  asm.with_retry do
    asm.mov(ebx, eax)
  end
end
