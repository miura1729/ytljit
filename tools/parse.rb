require 'rbconfig'

class Lex
  def initialize(str)
    @tokens = str.scan(/#.*?\n|\/\*.*?\*\/|[a-zA-Z_][a-zA-Z_0-9]*|-?[0-9]+\.?[0-9]*|\S/m).each
  end

  def get_next_token
    tok = @tokens.next
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

    when /\*/
      [:star, tok]

    else
      [:symbol, tok]
    end
  end
end

class StructInfo
  def initialize(struct_union)
    @kind = struct_union
    @name = name
    @member = []
  end

  attr :member
  attr_accessor :name
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
  when :id
    type = tok
    kind, tok = l.get_next_token
    parse_declare_vars(kind, tok, type, l)

  when :struct, :union
    @struct_stack.push StructInfo.new(kind)
    kind, tok = parse_struct(l)
    si = @struct_stack.pop
    parse_declare_vars(kind, tok, si, l)
  end
end

def parse_declare_vars(kind, tok, type, l)
  vtab = []
  if @struct_stack.last then
    vtab = @struct_stack.last.member
  end
  star_level = 0
  array_level = []
  begin
    var = tok
    while kind == :star do
      kind, tok = l.get_next_token
      star_level += 1
      var = tok
    end
    kind, tok = l.get_next_token
    while tok == '[' do
      kind, tok = l.get_next_token
      kind, tok = l.get_next_token
      array_level.push tok
      kind, tok = l.get_next_token
        end
    vtab.push [type, star_level, array_level, var]
  end while tok == ','
end

top(l)
    
@struct_table.each do |tag, body|
  p body
end

