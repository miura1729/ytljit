require 'parse'

f = File.read("#{Config::CONFIG["rubyhdrdir"]}/ruby/ruby.h")
l = Lex.new(f)
  
top(l)
  
@struct_table.each do |tag, body|
  print body.to_ytl
end
