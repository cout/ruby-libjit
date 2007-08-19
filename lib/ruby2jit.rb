require 'nodewrap'
require 'node_to_a'
require 'methodsig'
require 'jit'
require 'value'

class Node
  class CALL
    def libjit_compile(function, env)
      mid = self.mid
      args = self.args.to_a.map { |arg| arg.libjit_compile(function, env) }
      recv = self.recv.libjit_compile(function, env)

      end_label = JIT::Label.new

      result = function.value(JIT::Type::OBJECT)

      # TODO: This doesn't handle bignums
      binary_fixnum_operators = {
        :+ => proc { |lhs, rhs| lhs + (rhs & function.const(JIT::Type::INT, ~1)) },
        :- => proc { |lhs, rhs| lhs - (rhs & function.const(JIT::Type::INT, ~1)) },
        :< => proc { |lhs, rhs| lhs < rhs },
        :== => proc { |lhs, rhs| lhs == rhs },
      }

      # TODO: This optimization is only valid if Fixnum#+/- has not been
      # redefined
      if binary_fixnum_operators.include?(mid) then
        if args.length == 1 then
          call_label = JIT::Label.new
          recv_is_fixnum = recv.is_fixnum
          function.insn_branch_if_not(recv_is_fixnum, call_label)
          arg_is_fixnum = args[0].is_fixnum
          function.insn_branch_if_not(arg_is_fixnum, call_label)
          function.insn_store(
              result,
              binary_fixnum_operators[mid].call(recv, args[0]))
          function.insn_branch(end_label)
          function.insn_label(call_label)
        end
      end

      id = function.const(JIT::Type::ID, mid)
      num_args = function.const(JIT::Type::INT, args.length)
      function.insn_store(
        result,
        function.insn_call_native(:rb_funcall, 0, recv, id, num_args, *args))

      function.insn_label(end_label)
      return result
    end
  end

  class FCALL
    def libjit_compile(function, env)
      # TODO: might be better to use insn_push than alloca/store
      mid = self.mid
      args = self.args.to_a.map { |arg| arg.libjit_compile(function, env) }
      num_args = function.const(JIT::Type::INT, args.length)
      arg_array = function.insn_alloca(num_args)
      args.each_with_index do |arg, idx|
        function.insn_store_relative(arg_array, idx*4, arg)
      end
      id = function.const(JIT::Type::ID, mid)
      recv = function.const(JIT::Type::OBJECT, env.self)
      return function.insn_call_native(:rb_funcall2, 0, recv, id, num_args, arg_array)
    end
  end

  class LASGN
    def libjit_compile(function, env)
      value = self.value.libjit_compile(function, env)
      if not env.locals.include?(self.vid) then
        env.locals[self.vid] = value
      else
        function.insn_store(env.locals[self.vid], value)
      end
    end
  end

  class LVAR
    def libjit_compile(function, env)
      return env.locals[self.vid]
    end
  end

  class CONST
    def libjit_compile(function, env)
      klass = function.insn_call_native(:rb_class_of, 0, env.self)
      vid = function.const(JIT::Type::ID, self.vid)
      return function.insn_call_native(:rb_const_get, 0, klass, vid)
    end
  end

  class COLON3
    def libjit_compile(function, env)
      rb_cObject = function.const(JIT::Type::OBJECT, Object)
      vid = function.const(JIT::Type::ID, self.vid)
      return function.insn_call_native(:rb_const_get, 0, rb_cObject, vid)
    end
  end

  class LIT
    def libjit_compile(function, env)
      return function.const(JIT::Type::OBJECT, self.lit)
    end
  end

  class RETURN
    def libjit_compile(function, env)
      if self.stts then
        retval = self.stts.libjit_compile(function, env)
        function.insn_return(retval)
      else
        retval = function.const(JIT::Type::Object, nil)
        function.insn_return(retval)
      end
    end
  end

  class NEWLINE
    def libjit_compile(function, env)
      # TODO: This might not be quite right.  Basically, any time that
      # ruby_set_current_source is called, it gets the line number from
      # the node currently being evaluated.  Of course, since we aren't
      # evaluating nodes, that information will be stale.  There are a
      # number of places in eval.c where ruby_set_current_source is
      # called; we need to evaluate a dummy node for each of those
      # cases.
      # TODO: This breaks tracing, since we don't try to call the the
      # trace func.
      # TODO: We might be able to optimize this by keeping a mapping of
      # instruction offset to source line and only modifying
      # ruby_sourceline when an exception is raised (or other event that
      # reads ruby_sourceline).
      ruby_sourceline = function.ruby_sourceline()
      n = function.const(JIT::Type::INT, self.nd_line)
      function.insn_store_relative(ruby_sourceline, 0, n)
      self.next.libjit_compile(function, env)
    end
  end

  class BLOCK
    def libjit_compile(function, env)
      n = self
      while n do
        n.head.libjit_compile(function, env)
        n = n.next
      end
    end
  end

  class SCOPE
    def libjit_compile(function, env)
      case self.next
      when nil
      when Node::ARGS, Node::BLOCK_ARG then function.const(JIT::Type::Object, nil)
      else self.next.libjit_compile(function, env)
      end
    end
  end

  class ARGS
    def libjit_compile(function, env)
    end
  end

  class UNTIL
    def libjit_compile(function, env)
      start_label = JIT::Label.new
      end_label = JIT::Label.new
      function.insn_label(start_label)
      cond_is_false = self.cond.to_libjit_inverted_bool(function, env)
      function.insn_branch_if_not(cond_is_false, end_label)
      if self.body then
        self.body.libjit_compile(function, env)
      end
      function.insn_branch(start_label)
      function.insn_label(end_label)
    end
  end

  class WHILE
    def libjit_compile(function, env)
      start_label = JIT::Label.new
      end_label = JIT::Label.new
      function.insn_label(start_label)
      cond_is_false = self.cond.to_libjit_inverted_bool(function, env)
      function.insn_branch_if(cond_is_false, end_label)
      if self.body then
        self.body.libjit_compile(function, env)
      end
      function.insn_branch(start_label)
      function.insn_label(end_label)
    end
  end

  class IF
    def libjit_compile(function, env)
      else_label = JIT::Label.new
      cond_is_false = self.cond.to_libjit_inverted_bool(function, env)
      function.insn_branch_if(cond_is_false, else_label)
      if self.body then
        self.body.libjit_compile(function, env)
      end
      if self.else then
        end_label = JIT::Label.new
        function.insn_branch(end_label)
      end
      function.insn_label(else_label)
      if self.else then
        self.else.libjit_compile(function, env)
        function.insn_label(end_label)
      end
    end
  end

  class NOT
    def libjit_compile(function, env)
      is_false = self.body.to_libjit_inverted_bool(function, env)
      # 0 => 0 (Qfalse); 1 => 2 (Qtrue)
      one = function.const(JIT::Type::INT, 1)
      return function.insn_shl(is_false, one)
    end
  end

  def to_libjit_inverted_bool(function, env)
    #define RTEST(v) (((VALUE)(v) & ~Qnil) != 0)
    value = self.libjit_compile(function, env)
    qnil = function.const(JIT::Type::OBJECT, nil)
    not_qnil = function.insn_not(qnil)
    value_and_not_qnil = function.insn_and(value, not_qnil)
    zero = function.const(JIT::Type::INT, 0)
    return function.insn_eq(value_and_not_qnil, zero)
  end

  def to_libjit_bool(function, env)
    is_false = to_libjit_inverted_bool(function, env)
    is_true = function.insn_not(is_false)
    return is_true
  end

  class STR
    def libjit_compile(function, env)
      return function.const(JIT::Type::OBJECT, self.lit)
    end
  end

  class DSTR
    def libjit_compile(function, env)
      # TODO: Use rb_str_new, if String.new is not redefined
      rb_cString = function.const(JIT::Type::OBJECT, String)
      id_new = function.const(JIT::Type::ID, :new)
      id_to_s = function.const(JIT::Type::ID, :to_s)
      id_lshift = function.const(JIT::Type::ID, :<<)
      zero = function.const(JIT::Type::INT, 0)
      one = function.const(JIT::Type::INT, 1)
      str = function.insn_call_native(:rb_funcall, 0, rb_cString, id_new, zero)
      a = self.next.to_a
      a.each do |elem|
        v = elem.libjit_compile(function, env)
        s = function.insn_call_native(:rb_funcall, 0, v, id_to_s, zero)
        function.insn_call_native(:rb_funcall, 0, str, id_lshift, one, s)
      end
      return str
    end
  end

  class EVSTR
    def libjit_compile(function, env)
      return self.body.libjit_compile(function, env)
    end
  end
end

module JIT
  class NodeCompileEnvironment
    attr_reader :locals
    attr_accessor :self

    def initialize
      @locals = {}
      @self = nil
    end
  end
end

class Method
  def libjit_compile(optimization_level=2)
    env = JIT::NodeCompileEnvironment.new

    msig = self.signature
    if self.arity >= 0 then
      # all arguments required for this method
      signature = JIT::Type.create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::OBJECT ] * (1 + msig.arg_names.size))
    else
      # some arguments are optional for this method
      signature = JIT::Type::RUBY_VARARG_SIGNATURE
    end

    JIT::Context.build do |context|
      function = JIT::Function.compile(context, signature) do |f|
        if self.arity >= 0 then
          # all arguments required for this method
          env.self = f.get_param(0)
          msig.arg_names.each_with_index do |arg_name, idx|
            # TODO: how to deal with default values?
            env.locals[arg_name] = f.get_param(idx+1)
          end
        else
          # some arguments are optional for this method
          optional_args = {}
          args_node = args_node()
          opt = args_node.opt
          while opt do
            vid = opt.head.vid
            value = opt.head.value
            optional_args[vid] = value
            opt = opt.next
          end

          argc = f.get_param(0)
          argv = f.get_param(1)
          env.self = f.get_param(2)

          msig.arg_names.each_with_index do |arg_name, idx|
            if idx < msig.arg_names.size - optional_args.size then
              # TODO: use insn_load_elem
              env.locals[arg_name] = f.insn_load_relative(argv, idx*4, JIT::Type::OBJECT)
            else
              var = env.locals[arg_name] = f.value(JIT::Type::OBJECT)
              var_idx = f.const(JIT::Type::OBJECT, idx)
              have_this_arg = var_idx <= argc
              have_this_arg_label = JIT::Label.new
              next_arg_label = JIT::Label.new
              f.insn_branch_if(have_this_arg, have_this_arg_label)
              # this arg was not passed in
              f.insn_store(var, optional_args[arg_name].libjit_compile(f, env))
              f.insn_branch(next_arg_label)
              f.insn_label(have_this_arg_label)
              # this arg was passed in
              f.insn_store(var, f.insn_load_relative(argv, idx*4, JIT::Type::OBJECT))
              f.insn_label(next_arg_label)
            end
          end
        end

        f.optimization_level = optimization_level
        self.body.libjit_compile(f, env)
      end

      return function
    end
  end
end

if __FILE__ == $0 then

=begin
def gcd2(out, x, y)
  while x != y do
    # out.puts x
    if x < y
      y -= x
    else
      x -= y
    end
  end
  return x
end

require 'nodepp'
m = method(:gcd2)
# pp m.body
f = m.libjit_compile
puts f
puts gcd2($stdout, 1000, 1005)
p f.apply(nil, $stdout, 1000, 1005)
=end

  # TODO: implicit return values
=begin
def ack(m=0, n=0)
  if m == 0 then
    n + 1
  elsif n == 0 then
    ack(m - 1, 1)
  else
    ack(m - 1, ack(m, n - 1))
  end
end
=end

=begin
def ack(m=0, n=0)
  if m == 0 then
    return n + 1
  elsif n == 0 then
    return ack(m - 1, 1)
  else
    return ack(m - 1, ack(m, n - 1))
  end
end

require 'nodepp'
m = method(:ack)
# pp m.body
f = m.libjit_compile
# puts f
puts ack(0, 0)
p f.apply(self, 0, 0)
=end

def foo(m=42)
  puts m
end

m = method(:foo)
f = m.libjit_compile
# puts f
p f.apply(self)

end
