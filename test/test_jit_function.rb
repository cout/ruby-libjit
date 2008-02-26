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
        } .end
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
        } .end
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
        } .end
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
        } .end
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
        } .end
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
        } .end
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
        } .end
        f.insn_return result
      end
    end

    assert_equal(4, function.apply(0, 0))
  end

  def test_while_true_enters_loop
    function = nil
    JIT::Context.build do |context|
      signature = JIT::Type.create_signature(
          JIT::ABI::CDECL,
          JIT::Type::INT,
          [ ])
      function = JIT::Function.compile(context, signature) do |f|
        true_value = f.const(JIT::Type::INT, 1)
        false_value = f.const(JIT::Type::INT, 0)
        f.while(proc { true_value }) {
          f.insn_return true_value
        }.end
        f.insn_return false_value
      end
    end

    assert_equal(1, function.apply)
  end

  def test_while_true_reenters_loop
    function = nil
    JIT::Context.build do |context|
      signature = JIT::Type.create_signature(
          JIT::ABI::CDECL,
          JIT::Type::INT,
          [ ])
      function = JIT::Function.compile(context, signature) do |f|
        value = f.value(JIT::Type::INT)
        value.store(f.const(JIT::Type::INT, 0))
        f.while(proc { value < f.const(JIT::Type::INT, 2) }) {
          value.store(value + f.const(JIT::Type::INT, 1))
        }.end
        f.insn_return value
      end
    end

    assert_equal(2, function.apply)
  end

  def test_while_false_does_not_enter_loop
    function = nil
    JIT::Context.build do |context|
      signature = JIT::Type.create_signature(
          JIT::ABI::CDECL,
          JIT::Type::INT,
          [ ])
      function = JIT::Function.compile(context, signature) do |f|
        true_value = f.const(JIT::Type::INT, 1)
        false_value = f.const(JIT::Type::INT, 0)
        f.while(proc { false_value }) {
          f.insn_return true_value
        }.end
        f.insn_return false_value
      end
    end

    assert_equal(0, function.apply)
  end

  def test_until_false_enters_loop
    function = nil
    JIT::Context.build do |context|
      signature = JIT::Type.create_signature(
          JIT::ABI::CDECL,
          JIT::Type::INT,
          [ ])
      function = JIT::Function.compile(context, signature) do |f|
        true_value = f.const(JIT::Type::INT, 1)
        false_value = f.const(JIT::Type::INT, 0)
        f.until(proc { false_value }) {
          f.insn_return true_value
        }.end
        f.insn_return false_value
      end
    end

    assert_equal(1, function.apply)
  end

  def test_until_false_reenters_loop
    function = nil
    JIT::Context.build do |context|
      signature = JIT::Type.create_signature(
          JIT::ABI::CDECL,
          JIT::Type::INT,
          [ ])
      function = JIT::Function.compile(context, signature) do |f|
        value = f.value(JIT::Type::INT)
        value.store(f.const(JIT::Type::INT, 0))
        f.until(proc { value == f.const(JIT::Type::INT, 2) }) {
          value.store(value + f.const(JIT::Type::INT, 1))
        }.end
        f.insn_return value
      end
    end

    assert_equal(2, function.apply)
  end

  def test_until_true_does_not_enter_loop
    function = nil
    JIT::Context.build do |context|
      signature = JIT::Type.create_signature(
          JIT::ABI::CDECL,
          JIT::Type::INT,
          [ ])
      function = JIT::Function.compile(context, signature) do |f|
        true_value = f.const(JIT::Type::INT, 1)
        false_value = f.const(JIT::Type::INT, 0)
        f.until(proc { true_value }) {
          f.insn_return true_value
        }.end
        f.insn_return false_value
      end
    end

      assert_equal(0, function.apply)
  end

  # TODO: while/break
  # TODO: while/redo
  # TODO: until/break
  # TODO: until/redo
  # TODO: unless
  # TODO: elsunless
end

