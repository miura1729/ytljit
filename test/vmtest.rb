# test program
require 'ytljit'
require 'pp'

include YTLJit
is = RubyVM::InstructionSequence.compile(
        "class Foo; def test(x);a = 0;lambda {a = a + 1};p a;end;end","", "", 0,
              {  :peephole_optimization    => true,
                 :inline_const_cache       => false,
                 :specialized_instruction  => false,}
     ).to_a
iseq = VMLib::InstSeqTree.new(nil, is)

tr = VM::YARVTranslatorSimple.new([iseq])
tr.translate


