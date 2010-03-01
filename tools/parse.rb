require 'rbconfig'
require 'pp'

class Lex
  def initialize(str)
    @tokens = str.scan(/#.*?\n|\/\*.*?\*\/|[a-zA-Z_][a-zA-Z_0-9]*|-?[0-9]+\.?[0-9]*|\S/m).each
  end

  KEYWORD = {
    'struct' => :struct,
    'union' => :union,
    'typedef' => :typedef,
    'const' => :const,
    'volatile' => :volatile,
    'registor' => :regstor,
    'unsigned' => :unsigned,
    'signed' => :signed,
    'char' => :char,
    'int' => :int,
    'VALUE' => :user_type,
    'short' => :short,
    'long' => :long,
    'float' => :float,
    'double' => :double,
  }

  def get_next_token
    tok = @tokens.next
    id = nil
    if id = KEYWORD[tok] then
      return [id, tok]
    end

    case tok 
    when /^#/
      [:preprocess, tok]

    when /^\/\*/
      [:comment, tok]

    when /^struct$/
      [:struct, tok]

    when /^union$/
      [:union, tok]

    when /[a-zA-Z_]/
      [:id, tok]

    when /[-0-9]/
      [:number, tok]

    when /\{/
      [:open_bre, tok]

    when /\(/
      [:open_par, tok]

    when /\*/
      [:star, tok]

    else
      [:symbol, tok]
    end
  end
end

class VarInfo
  def initialize(type, name)
    @type = type
    @name = name
  end

  def inspect
    "#{@type} #{@name}\n"
  end

  def sizeof
    case @type
    when 'char', 'unsigned char', 'signed char'
      1
    when 'short', 'unsigned short'
      2
    when 'int', 'unsigned', 'unsigned long', 'long', 'VALUE', 'BDIGIT'
      4
    when 'double'
      8
    else
      @type.sizeof
    end   
  end

  attr :type
  attr :name
end

class StructInfo
  def initialize(struct_union)
    @kind = struct_union
    @name = name
    @member = []
  end

  def inspect
    rs = "#{@kind.to_s} #{@name} {\n"
    @member.each do |e|
      rs += e.inspect
    end
    rs += "}\n"
  end

  def sizeof
    siz = 0
    @member.each do |mem|
      siz += mem.sizeof
    end
    siz
  end

  attr :member
  attr_accessor :name
end

class FuncPtrInfo
  def initialize(ret, arg, name)
    @name = name
    @return_type = ret
    @argument_type = arg
  end

  def inspect
    "#{@return_type.inspect} (*#{@name})(#{@argument_type.inspect})"
  end

  def sizeof
    4
  end

  attr :name
  attr :return_type
  attr :argument_type
end

class PtrInfo
  def initialize(ent)
    @entity = ent
  end

  def inspect
    "*#{@entity.inspect}"
  end

  def sizeof
    4
  end
end

class ArrayInfo
  def initialize(ent, size)
    @entity = ent
    @size = size
  end

  def inspect
    "#{@entity.inspect}[#{@size}]"
  end

  def sizeof
    @entity.sizeof * @size.to_i
  end
end

@struct_table = {}
@struct_stack = []

f = File.read("#{Config::CONFIG["rubyhdrdir"]}/ruby/ruby.h")
l = Lex.new(f)

def top(l)
  kind, tok = l.get_next_token
  loop do
    case kind
    when :struct, :union
      @struct_stack.push StructInfo.new(kind)
      kind, tok = parse_struct(l)
      @struct_stack.pop

    when :typedef
      kind, tok = l.get_next_token
      p parse_declare(kind, tok, l)

    else
      kind, tok = l.get_next_token
    end
  end
end

def parse_struct(l)
  kind, tok = l.get_next_token
  case kind
  when :id
    if @struct_table[tok] then
      @struct_stack.pop
      @struct_stack.push @struct_table[tok]
    else
      si = @struct_stack.last
      si.name = tok
      @struct_table[tok] = si
    end
    parse_struct_with_tag(tok, l)

  when :open_bre
    parse_struct_body(l)

  else
    [kind, tok]
  end
end

def parse_struct_with_tag(tag, l)
  kind, tok = l.get_next_token
  if kind == :open_bre then
    parse_struct_body(l)
  else
    [kind, tok]
  end
end

def parse_struct_body(l)
  kind, tok = l.get_next_token
  while tok != '}' do
    parse_declare(kind, tok, l)
    kind, tok = l.get_next_token
  end
  l.get_next_token
end

def parse_declare(kind, tok, l)
  case kind
  when :signed, :unsigned
    type = tok
    kind, tok = l.get_next_token
    if parse_declare_simple_type(kind, tok, l) == nil then
      parse_declare_vars('int', kind, tok, l)
    end

  when :typedef
    type = tok
    kind, tok = l.get_next_token
    parse_declare(kind, tok, l)

  when :struct, :union
    @struct_stack.push StructInfo.new(kind)
    kind, tok = parse_struct(l)
    si = @struct_stack.pop
    parse_declare_vars(si, kind, tok, l)

  else
    parse_declare_simple_type(kind, tok, l)
  end
end

def parse_declare_simple_type(kind, tok, l)
  if [:char, :int, :user_type,  :long, :short, :float, :double].include?(kind)
    type = tok
    kind, tok = l.get_next_token
    parse_declare_vars(type, kind, tok, l)
    true
  else
    nil
  end
end

def parse_declare_var(type, kind, tok, l)
  if kind == :open_par then
    return [parse_declare_funcptr(type, l), kind, tok]
  end
  
  star_level = 0
  array_level = []
  var = tok

  while kind == :star do
    kind, tok = l.get_next_token
    star_level += 1
    var = tok
  end
  
  kind, tok = l.get_next_token
  while tok == '[' do
    kind, tok = l.get_next_token
    array_level.push tok
    kind, tok = l.get_next_token
  end

  res = VarInfo.new(type, var)
  while star_level > 0 do
    star_level -= 1
    res = PtrInfo.new(res)
  end
  while array_level.size > 0 do
    as = array_level.pop
    res = ArrayInfo.new(res, as)
  end

  [res, kind, tok]
end

def parse_declare_vars(type, kind, tok, l)
  vtab = []
  if @struct_stack.last then
    vtab = @struct_stack.last.member
  end
  begin
    vinfo, kind, tok = parse_declare_var(type, kind, tok, l)
    vtab.push vinfo
  end while tok == ','
end

def parse_declare_funcargs(l)
  begin
    kind, tok = l.get_next_token
  end while tok != ')'
  []
end

def parse_declare_funcptr(rettype, l)
  kind, tok = l.get_next_token
  vinfo, kind, tok = parse_declare_var(rettype, kind, tok, l)
  kind, tok = l.get_next_token
  if kind == :open_par then
    args = parse_declare_funcargs(l)
    FuncPtrInfo.new(rettype, args, vinfo)
  else
    vinfo
  end
end

top(l)
    
@struct_table.each do |tag, body|
  pp body
  p body.sizeof
end

