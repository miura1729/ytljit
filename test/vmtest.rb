# test program
require 'ytljit'
require 'pp'

include YTLJit
is = RubyVM::InstructionSequence.compile(
#       "class Foo; def test(x);a = 0;lambda {a = a + 1};p a;end;end","", "", 0,
#        "b = 0;def test(x);a = 0;lambda {a = a + 1};p a;end;test(0)","", "", 0,
        "def test(x);p x;end;test(0)","", "", 0,
              {  :peephole_optimization    => true,
                 :inline_const_cache       => false,
                 :specialized_instruction  => false,}
     ).to_a
iseq = VMLib::InstSeqTree.new(nil, is)
pp iseq

tr = VM::YARVTranslatorSimple.new([iseq])
context = VM::Context.new
#tr.translate.compile(context)
tnode = tr.translate
tnode.inspect_by_graph
context = tnode.compile(context)
tnode.code_space.disassemble
# context.code_space.disassemble




