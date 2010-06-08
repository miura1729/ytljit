# test program
require 'ytljit'

include YTLJit
is = RubyVM::InstructionSequence.compile(
              "def test(x);a = a + 1;p a;end","", "", 0,
              {  :peephole_optimization    => true,
                 :inline_const_cache       => false,
                 :specialized_instruction  => false,}
     ).to_a
iseq = VMLib::InstSeqTree.new(nil, is)


tr = VM::YARVTranslatorSimple.new([iseq])
tr.translate


