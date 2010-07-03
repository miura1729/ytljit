# test program
require 'ytljit'
require 'pp'

include YTLJit
is = RubyVM::InstructionSequence.compile(
#       "class Foo; def test(x);a = 0;lambda {a = a + 1};p a;end;end","", "", 0,
#        "b = 0;def test(x);a = 0;lambda {a = a + 1};p a;end;test(0)","", "", 0,
#         "def test(x);a = x + 1;p a; p x;end;test(3)","", "", 0,
        "def test(x);if x then a = 1 else a = 3 end;p a end;test(3)","", "", 0,
              {  :peephole_optimization    => true,
                 :inline_const_cache       => false,
                 :specialized_instruction  => false,}
     ).to_a
iseq = VMLib::InstSeqTree.new(nil, is)
pp iseq

tr = VM::YARVTranslatorSimple.new([iseq])
#tr.translate.compile(context)
tnode = tr.translate
tnode.inspect_by_graph
context = VM::Context.new(tnode)
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
tnode.code_space.call(tnode.code_space.base_address)
p tnode.code_space_tab

