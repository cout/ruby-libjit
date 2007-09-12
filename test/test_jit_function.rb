require 'jit/function'
require 'jit/value'
require 'test/unit'

class TestJitFunction < Test::Unit::TestCase
  def test_if_false
    function = nil
    JIT::Context.build do |context|
      signature = JIT::Type.create_signature(
          JIT::ABI::CDECL,
          JIT::Type::INT,
          [ JIT::Type::INT ])
      function = JIT::Function.compile(context, signature) do |f|
        result = f.value(JIT::Type::INT)
        result.store f.const(JIT::Type::INT, 1)
        f.if(f.get_param(0)) {
          result.store f.const(JIT::Type::INT, 2)
        }
        f.insn_return result
      end
    end

    assert_equal(1, function.apply(0))
  end

  def test_if_true
    function = nil
    JIT::Context.build do |context|
      signature = JIT::Type.create_signature(
          JIT::ABI::CDECL,
          JIT::Type::INT,
          [ JIT::Type::INT ])
      function = JIT::Function.compile(context, signature) do |f|
        result = f.value(JIT::Type::INT)
        result.store f.const(JIT::Type::INT, 1)
        f.if(f.get_param(0)) {
          result.store f.const(JIT::Type::INT, 2)
        }
        f.insn_return result
      end
    end

    assert_equal(2, function.apply(1))
  end

  def test_if_false_else
    function = nil
    JIT::Context.build do |context|
      signature = JIT::Type.create_signature(
          JIT::ABI::CDECL,
          JIT::Type::INT,
          [ JIT::Type::INT ])
      function = JIT::Function.compile(context, signature) do |f|
        result = f.value(JIT::Type::INT)
        result.store f.const(JIT::Type::INT, 1)
        f.if(f.get_param(0)) {
          result.store f.const(JIT::Type::INT, 2)
        } .else {
          result.store f.const(JIT::Type::INT, 3)
        }
        f.insn_return result
      end
    end

    assert_equal(3, function.apply(0))
  end

  def test_if_true_else
    function = nil
    JIT::Context.build do |context|
      signature = JIT::Type.create_signature(
          JIT::ABI::CDECL,
          JIT::Type::INT,
          [ JIT::Type::INT ])
      function = JIT::Function.compile(context, signature) do |f|
        result = f.value(JIT::Type::INT)
        result.store f.const(JIT::Type::INT, 1)
        f.if(f.get_param(0)) {
          result.store f.const(JIT::Type::INT, 2)
        } .else {
          result.store f.const(JIT::Type::INT, 3)
        }
        f.insn_return result
      end
    end

    assert_equal(2, function.apply(1))
  end

  def test_if_false_else_if_true_else
    function = nil
    JIT::Context.build do |context|
      signature = JIT::Type.create_signature(
          JIT::ABI::CDECL,
          JIT::Type::INT,
          [ JIT::Type::INT, JIT::Type::INT ])
      function = JIT::Function.compile(context, signature) do |f|
        result = f.value(JIT::Type::INT)
        result.store f.const(JIT::Type::INT, 1)
        f.if(f.get_param(0)) {
          result.store f.const(JIT::Type::INT, 2)
        } .elsif(f.get_param(1)) {
          result.store f.const(JIT::Type::INT, 3)
        } .else {
          result.store f.const(JIT::Type::INT, 4)
        }
        f.insn_return result
      end
    end

    assert_equal(3, function.apply(0, 1))
  end

  def test_if_true_else_if_false_else
    function = nil
    JIT::Context.build do |context|
      signature = JIT::Type.create_signature(
          JIT::ABI::CDECL,
          JIT::Type::INT,
          [ JIT::Type::INT, JIT::Type::INT ])
      function = JIT::Function.compile(context, signature) do |f|
        result = f.value(JIT::Type::INT)
        result.store f.const(JIT::Type::INT, 1)
        f.if(f.get_param(0)) {
          result.store f.const(JIT::Type::INT, 2)
        } .elsif(f.get_param(1)) {
          result.store f.const(JIT::Type::INT, 3)
        } .else {
          result.store f.const(JIT::Type::INT, 4)
        }
        f.insn_return result
      end
    end

    assert_equal(2, function.apply(1, 0))
  end

  def test_if_false_else_if_false_else
    function = nil
    JIT::Context.build do |context|
      signature = JIT::Type.create_signature(
          JIT::ABI::CDECL,
          JIT::Type::INT,
          [ JIT::Type::INT, JIT::Type::INT ])
      function = JIT::Function.compile(context, signature) do |f|
        result = f.value(JIT::Type::INT)
        result.store f.const(JIT::Type::INT, 1)
        f.if(f.get_param(0)) {
          result.store f.const(JIT::Type::INT, 2)
        } .elsif(f.get_param(1)) {
          result.store f.const(JIT::Type::INT, 3)
        } .else {
          result.store f.const(JIT::Type::INT, 4)
        }
        f.insn_return result
      end
    end

    assert_equal(4, function.apply(0, 0))
  end
end

