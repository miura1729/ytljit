require 'test/unit'
# require 'test'
# require 'minitest/autorun'
require '../lib/ytljit.rb'
# require '../lib/ytljit/ytljit.rb'

include YTLJit::TypeUtil

class TreeTests < Test::Unit::TestCase

  def test_tree
    tree = KlassTree.new

    tree.add([0], :int)
    tree.add([1.0], :float)
    tree.add([2], :fixnum)
    tree.add([[]], :a)

    assert_equal(tree.search([[]]).value, :a)
    assert_equal(tree.search([2]).value, :fixnum)
    assert_equal(tree.search([1.0]).value, :float)
    assert_equal(tree.search([]).value, [])
  end
end
