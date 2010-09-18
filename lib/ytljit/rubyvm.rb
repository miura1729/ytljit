# -*- coding: cp932 -*-
#
#  rubyvm.rb - structured bytecode library
#
#
module VMLib
  class InstSeqTree
    Headers = %w(magic major_version minor_version format_type
                 misc name filename filepath line type locals args 
                 exception_table)

#  call-seq:
#     VMLib::InstSeqTree.new(parent, iseq)
#        parent  Partent of InstSeqTree
#                For example, when you will construct InstSeqTree of
#                the method body, you must 'parent' is InstSeqTree of definition
#                code of the method.
#                If parent is none, 'parent' is nil.
#        iseq    Instruction Sequence, Normally the result of 
#                VM::InstructionSequence.compile(...) or 
#                VM::InstructionSequence.compile_file(...)
    def initialize(parent = nil, iseq = nil)
      @lblock = {}
      @lblock_list = [nil]

      @header = {}
      @body = nil
      @parent = parent

      Headers.each do |name|
        @header[name] = nil
      end
      
      if iseq then
        init_from_ary(iseq.to_a)
      end
    end

    attr          :header
    attr_accessor :body
    attr          :parent
    
    def init_from_ary(ary)
      i = 0
      Headers.each do |name|
        @header[name] = ary[i]
        i = i + 1
      end

      @body = ary[i]
    end

    def to_a
      res = []
      Headers.each do |name|
        res.push @header[name]
      end
      
      res.push @body
      res
    end
  end
end
