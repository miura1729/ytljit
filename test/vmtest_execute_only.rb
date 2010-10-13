# test program
require 'ytljit'
require 'pp'

include YTLJit
tnode = nil

File.open("out.marshal") do |fp|
  tnode = Marshal.load(fp.read)
end
tnode.code_space_tab.each do |cs|
  cs.update_refer
end

tnode.code_space_tab.each do |cs|
  cs.fill_disasm_cache
end
tnode.code_space.disassemble

tnode.code_space.call(tnode.code_space.base_address)


