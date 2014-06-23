# test program
# require 'ytljit'
require 'test/unit'
require '../lib/ytljit.rb'
require 'pp'

include YTLJit

class InstructionTests < Test::Unit::TestCase

  def test_x
    emit compile "p 'hello'"
    # emit compile "class Foo; def test(x);a = 0; x= 1;lambda {a = a + 1};p a;end;end"
    #        "b = 0;def test(x);a = 0;lambda {a = a + 1};p a;end;test(0)"
    #         "def test(x);a = x + 1;p a; p x;end;test(3)"
    #        "def test(x);if x then a = 1 else a = 3 end;p a end;test(3)"
    #        "def test(x);if x == 3 then a = 1 else a = 3 end;p a end;test(3)"
    #        "def fib(x);if x < 2 then 1 else fib(x + -1) + fib(x + -2) end;end;p fib(35)"
    #        "def fib(x);if x < 2 then 1 else fib(x - 1) + fib(x  - 2) end;end;p fib(35)"
    #        "def ffib(x);if x < 2 then 1.0 else ffib(x + -1) + ffib(x + -2) end;end;p ffib(5)"
    #        "def foo; [1, 2, 3][0] + [1, 2, 3][1]  end; p foo"
    #        "def foo(x); if x then x = 1 else x = 2 end; x; end; p foo(1)"
    #        "def foo(x); if x then x = 2.0 else x = 1 end; x; end; p foo(1)"
    #         "def foo(x); yield(x) + 2; end; p foo(1) {|a| a + 1}"
    #         "def id(x); x; end; p id(1); p id(1.0)"
    #         "def id(x); x; end; p id(1); p id(1.0); def id2(x) x end; id2(1)"
    #           "def mul(x); x * x; end; p mul(20);p mul(30.0)"
    #          "def div(x, y); x / y; end; p div(20, 10);p div(30.0, -12.0)"
    #          "def div(x, y); x / y; end; p div(-20, 10);p div(30.0, -12.0)"
  end

  def _test_div
       emit compile "def div(x, y); x / y; end; p div(-20, 10);p div(30.0, -12.0)"
  end

  def compile code
#        "1.1"
    is = RubyVM::InstructionSequence.compile(code, "",
                                             "", 0,
        {  :peephole_optimization    => true,
           :inline_const_cache       => false,
           :specialized_instruction  => false,}
    ).to_a
  end
  def emit is
    iseq = VMLib::InstSeqTree.new(nil, is)
    pp iseq

    tr = VM::YARVTranslatorSimple.new([iseq])
#tr.translate.compile(context)
    tnode = tr.translate
# tnode.inspect_by_graph
    context = VM::CollectInfoContext.new(tnode)
    tnode.collect_info(context)
    context = VM::TypeInferenceContext.new(tnode)
    begin
      pp "do type inference"
      tnode.collect_candidate_type(context, [], [])
      pp context.convergent
    end until context.convergent
    tnode.collect_candidate_type(context, [], [])

    # tnode = Marshal.load(Marshal.dump(tnode)) kf hack
    context = VM::CompileContext.new(tnode)
    context.options = {:disp_signature => true}
    tnode.compile(context)
# context.code_space.disassemble
    p tnode.code_space
# tnode.code_space.disassemble
=begin
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
  end



end
