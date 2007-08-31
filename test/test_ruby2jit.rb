require 'test/unit/autorunner'
require 'test/unit/testcase'
require 'ruby2jit'

class TestRuby2Jit < Test::Unit::TestCase
  def compile_and_run(obj, method)
    m = obj.method(method)
    f = m.libjit_compile
    f.apply(obj)
  end

  def test_raise
    foo = Class.new do
      include Test::Unit::Assertions
      def foo
        raise "FOO!"
      end
    end
    assert_raise(RuntimeError) do
      compile_and_run(foo.new, :foo)
    end
  end

  def test_reassign_no_block
    foo = Class.new do
      include Test::Unit::Assertions
      def foo
        a = 1
        a = 2
        assert_equal(2, a)
      end
    end
    compile_and_run(foo.new, :foo)
  end

  def test_reassign_with_block
    foo = Class.new do
      include Test::Unit::Assertions
      def foo
        a = 1
        a = 2
        [].each { }
        assert_equal(2, a)
      end
    end
    compile_and_run(foo.new, :foo)
  end

  def test_two_block_args_passed_two_values
    foo = Class.new do
      include Test::Unit::Assertions
      def foo
        [ [1, 2] ].each do |x, y|
          assert_equal 1, x
          assert_equal 2, y
        end
      end
    end
    compile_and_run(foo.new, :foo)
  end

  def test_two_block_args_passed_three_values
    foo = Class.new do
      include Test::Unit::Assertions
      def foo
        [ [1, 2, 3] ].each do |x, y|
          assert_equal 1, x
          assert_equal [2, 3], y
        end
      end
    end
    compile_and_run(foo.new, :foo)
  end

  def test_block_inside_else
    foo = Class.new do
      include Test::Unit::Assertions
      def foo
        a = "FOO"
        assert_equal("FOO", a)
        if true then
          assert_equal("FOO", a)
        else
          [].each { false }
        end
        assert_equal("FOO", a)
      end
    end
    compile_and_run(foo.new, :foo)
  end
end

if __FILE__ == $0 then
  exit Test::Unit::AutoRunner.run #(true)
end

