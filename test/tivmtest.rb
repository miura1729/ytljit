# test program
require 'ytljit'
require 'pp'

include YTLJit
is = RubyVM::InstructionSequence.compile(
        "def typeinf; p @name; end ; typeinf","", "", 0,
#        "def typeinf; p @name; end ; ","", "", 0,
              {  :peephole_optimization    => true,
                 :inline_const_cache       => false,
                 :specialized_instruction  => false,}
     ).to_a
iseq = VMLib::InstSeqTree.new(nil, is)
pp iseq

tr = VM::YARVTranslatorTypeInference.new([iseq])
#tr = VM::YARVTranslatorSimple.new([iseq])
context = VM::YARVContext.new
class Foo;def initialize;@name = :foo;end;end
foo = Foo.new
context.slf = foo
tnode = tr.translate(context)
tnode.inspect_by_graph
context = VM::CollectInfoContext.new(tnode)
context = tnode.collect_info(context)

context = VM::CompileContext.new(tnode)
context = tnode.compile(context)
# context.code_space.disassemble
p tnode.code_space
# tnode.code_space.disassemble
=begin
tnode = Marshal.load(Marshal.dump(tnode))
asm = Assembler.new(tnode.code_space)
asm.with_retry do
end
tnode.code_space.disassemble
=end
tnode.code_space_tab.each do |cs|
  cs.fill_disasm_cache
end
tnode.code_space.disassemble

tnode.code_space.call(tnode.code_space.base_address)

