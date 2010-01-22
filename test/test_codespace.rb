require 'test/unit'
require 'lib/ytljit/ytljit.rb'

class CodeSpaceTests < Test::Unit::TestCase
  include YTLJit

  def test_emit
    cs = CodeSpace.new
    cs[0] = "Hello"
    assert_equal(cs.to_s, "Hello")
    cs.emit("World")
    assert_equal(cs.to_s, "HelloWorld")
  end

  def test_ref
    cs = CodeSpace.new
    cs[0] = "Hello"
    assert_equal(cs[1], 'e'.ord)
    p cs.base_address.to_s(16)
  end
end
