require 'nodewrap'
require 'node_to_a'
require 'methodsig'
require 'jit'

class Node
  class CALL
    def libjit_compile(function, env)
      recv = self.recv.libjit_compile(function, env)
      id = function.value(JIT::Type::ID, self.mid)
      args = self.args.to_a.map { |arg| arg.libjit_compile(function, env) }
      num_args = function.value(JIT::Type::INT, args.length)
      function.insn_call_native(:rb_funcall, 0, recv, id, num_args, *args)
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

  class LIT
    def libjit_compile(function, env)
      return function.value(JIT::Type::OBJECT, self.lit)
    end
  end

  class RETURN
    def libjit_compile(function, env)
      if self.stts then
        retval = self.stts.libjit_compile(function, env)
        function.insn_return(retval)
      else
        retval = function.value(JIT::Type::Object, nil)
        function.insn_return(retval)
      end
    end
  end

  class NEWLINE
    def libjit_compile(function, env)
      # TODO
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
      when Node::ARGS, Node::BLOCK_ARG then function.value(JIT::Type::Object, nil)
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
      one = function.value(JIT::Type::INT, 1)
      return function.insn_shl(is_false, one)
    end
  end

  def to_libjit_inverted_bool(function, env)
    #define RTEST(v) (((VALUE)(v) & ~Qnil) != 0)
    value = self.libjit_compile(function, env)
    qnil = function.value(JIT::Type::OBJECT, nil)
    not_qnil = function.insn_not(qnil)
    value_and_not_qnil = function.insn_and(value, not_qnil)
    zero = function.value(JIT::Type::INT, 0)
    return function.insn_eq(value_and_not_qnil, zero)
  end

  def to_libjit_bool(function, env)
    is_false = to_libjit_inverted_bool(function, env)
    is_true = function.insn_not(is_false)
    return is_true
  end

  class STR
    def libjit_compile(function, env)
      return function.value(JIT::Type::OBJECT, self.lit)
    end
  end

  class DSTR
    def libjit_compile(function, env)
      # TODO: Use rb_str_new, if String.new is not redefined
      rb_cString = function.value(JIT::Type::OBJECT, String)
      id_new = function.value(JIT::Type::ID, :new)
      id_to_s = function.value(JIT::Type::ID, :to_s)
      id_lshift = function.value(JIT::Type::ID, :<<)
      zero = function.value(JIT::Type::INT, 0)
      one = function.value(JIT::Type::INT, 1)
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

    def initialize
      @locals = {}
    end
  end
end

class Method
  def libjit_compile
    env = JIT::NodeCompileEnvironment.new
    signature = JIT::Type.create_signature(
      self.arity >= 0 ? JIT::ABI::CDECL : JIT::ABI::VARARG,
      JIT::Type::OBJECT,
      [ JIT::Type::OBJECT ] * self.arity.abs)
    JIT::Context.build do |context|
      function = JIT::Function.compile(context, signature) do |f|
        msig = self.signature
        msig.arg_names.each_with_index do |arg_name, idx|
          # TODO: how to deal with default values?
          env.locals[arg_name] = f.get_param(idx)
        end
        self.body.libjit_compile(f, env)
      end
      return function
    end
  end
end

=begin
def foo(x, y)
  return x + y
end

m = method(:foo)
f = m.libjit_compile
puts f
p f.apply(1, 2)
=end

# def gcd2(x, y)
#   while x != y do
#     if x < y
#       y -= x
#     else
#       x -= y
#     end
#   end
#   return x
# end

def gcd2(out, x, y)
  while x != y do
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
# puts f
puts gcd2($stdout, 1000, 1005)
p f.apply($stdout, 1000, 1005)

