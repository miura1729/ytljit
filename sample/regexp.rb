require 'ytljit.rb'

include YTLJit

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
    @transfer[true] = []
    @isend = false
  end

  def reset
    @transfer = {}
    @transfer[nil] = []
    @transfer[true] = []
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
    trans[true] = []
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
        (nodes + trans[true]).each_cons(2) do |e0, e1|
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
      if c != nil then
        st.each do |ele|
          res += "  #{c} -> #{ele.id} #{"  END" if @isend}\n"
        end
      end
    end

    res
  end
end

class StateCompiler
  def initialize
    @state_codespace = []
    State.states.each do |s|
      @state_codespace[s.id] = CodeSpace.new
    end
    @csstart = CodeSpace.new
    @csstart2 = CodeSpace.new
    @csmain = CodeSpace.new
    @failend = CodeSpace.new
  end

  #  Register map
  #
  # eax work 
  # esi work
  # edi pointer to current char
  def compile_1state(st)
    cstab =  @state_codespace
    ccs = @state_codespace[st.id]
    asm = Assembler.new(ccs)
    if st.isend then
      asm.with_retry do
        asm.mov(X86::EAX, OpImmidiate32.new(2))
        asm.ret
      end
    else
      failend = @failend
      asm.with_retry do
        asm.mov(X86::AL, X86::INDIRECT_EDI)
        asm.add(X86::EDI, OpImmidiate32.new(1))
        st.transfer.each do |c, ns|
          if c.is_a?(String) then
            asm.cmp(X86::AL, OpImmidiate8.new(c.ord))
            asm.jz(cstab[ns[0].id].var_base_address)
          end
        end
        asm.cmp(X86::AL, OpImmidiate8.new(0))
        asm.jz(failend.var_base_address)
        if st.transfer[true][0] then
          asm.jmp(cstab[st.transfer[true][0].id].var_base_address)
        else
          asm.mov(X86::EAX, OpImmidiate32.new(0))
          asm.ret
        end
      end
    end
  end

  def compile
    asm = Assembler.new(@csstart)
    cs2 = @csstart2
    asm.with_retry do
      asm.mov(X86::ESI, X86::EAX)
      asm.jmp(cs2.var_base_address)
    end
    RubyType::rstring_ptr(X86::ESI, @csstart2, @csmain)

    asm = Assembler.new(@csmain)
    cstab =  @state_codespace
    asm.with_retry do
      asm.mov(X86::EDI, X86::EAX)
      asm.jmp(cstab[0].var_base_address)
    end

    asm = Assembler.new(@failend)
    asm.with_retry do
      asm.mov(X86::EAX, OpImmidiate32.new(0))
      asm.ret
    end

    State.states.each do |s|
      compile_1state(s)
    end
  end

  def exec(str)
    @csstart.call(@csstart.base_address, str)
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

    when '.'
      if orxst then
        s2 = orxst
        orxst = nil
      else
        s2 = State.new
      end
      s1.add_edge(true, s2)
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
#s, e = parse("c(abc)*a|b|c")
s, e = parse(".*cabc.*a|b|c")
State.states.each do |s|
  s.translate_dfa
end

State.states.each do |s|
  p s
end

sc = StateCompiler.new
sc.compile
p sc.exec("foo")
p sc.exec("cabcd")
p sc.exec("cabcccaasssccccddswa")
