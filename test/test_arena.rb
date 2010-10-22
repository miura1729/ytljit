require 'test/unit'
require 'ytljit'

include YTLJit
include YTLJit::Runtime

class ArenaTests < Test::Unit::TestCase
  VALUE = AsmType::MACHINE_WORD
  P_CHAR = AsmType::Pointer.new(AsmType::INT8)

  RBasic = AsmType::Struct.new(
              VALUE, :flags,
              VALUE, :klass
             )
  RString = AsmType::Struct.new(
               RBasic, :basic,
               AsmType::Union.new(
                AsmType::Struct.new(
                 AsmType::INT32, :len,
                 P_CHAR, :ptr,
                 AsmType::Union.new(
                   AsmType::INT32, :capa,
                   VALUE, :shared,
                 ), :aux
                ), :heap,
                AsmType::Array.new(
                   AsmType::INT8,
                   24
                ), :ary
               ), :as
              )
  def test_arena
    arena = Arena.new
    foo = TypedDataArena.new(RString, arena, 32)
    foo[:basic][:flags].ref = 10
    foo[:as][:heap][:aux][:capa].ref = 320
    assert_equal(foo[:basic][:flags].ref, 10)
    assert_equal(foo[:as][:heap][:aux][:shared].ref, 320)
  end
end

