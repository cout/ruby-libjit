require 'nodewrap'
require 'node_to_a'
require 'methodsig'
require 'jit'
require 'value'

def debug_print_object(f, obj)
  f.insn_call_native(
      :rb_funcall,
      0,
      f.const(JIT::Type::OBJECT, $stdout),
      f.const(JIT::Type::ID, :puts),
      f.const(JIT::Type::INT, 1),
      obj)
end

class Node
  class FALSENODE
    def libjit_compile(function, env)
      return function.const(JIT::Type::OBJECT, false)
    end
  end

  class TRUENODE
    def libjit_compile(function, env)
      return function.const(JIT::Type::OBJECT, true)
    end
  end

  class NILNODE
    def libjit_compile(function, env)
      return function.const(JIT::Type::OBJECT, nil)
    end
  end

  class CALL
    def libjit_compile(function, env)
      mid = self.mid
      if self.args then
        args = self.args.to_a.map { |arg| arg.libjit_compile(function, env) }
      else
        args = []
      end
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
      call_result = function.insn_call_native(:rb_funcall, 0, recv, id, num_args, *args)
      function.insn_store(result, call_result)

      function.insn_label(end_label)
      return result
    end
  end

  class FCALL
    def libjit_compile(function, env)
      mid = self.mid
      if self.args then
        args = self.args.to_a.map { |arg| arg.libjit_compile(function, env) }
      else
        args = []
      end
      num_args = function.const(JIT::Type::INT, args.length)
      array_type = JIT::Type.create_struct([ JIT::Type::OBJECT ] * args.length)
      array = function.value(array_type)
      array_ptr = function.insn_address_of(array)
      args.each_with_index do |arg, idx|
        function.insn_store_elem(array_ptr, function.const(JIT::Type::INT, idx), arg)
      end
      id = function.const(JIT::Type::ID, mid)
      recv = function.const(JIT::Type::OBJECT, env.frame.self)
      return function.insn_call_native(:rb_funcall2, 0, recv, id, num_args, array_ptr)
    end
  end

  class ATTRASGN
    def libjit_compile(function, env)
      mid = self.mid
      args = self.args.to_a.map { |arg| arg.libjit_compile(function, env) }
      recv = self.recv.libjit_compile(function, env)
      id = function.const(JIT::Type::ID, mid)
      num_args = function.const(JIT::Type::INT, args.length)
      result = function.insn_call_native(:rb_funcall, 0, recv, id, num_args, *args)
      function.insn_return(result)
      return result
    end
  end

  class LASGN
    def libjit_compile(function, env)
      value = self.value.libjit_compile(function, env)
      return env.scope.local_set(self.vid, value)
    end
  end

  class LVAR
    def libjit_compile(function, env)
      return env.scope.local_get(self.vid)
    end
  end

=begin
  class DVAR
    def libjit_compile(function, env)
      # TODO: should this really be the same as LVAR?
      return env.locals[self.vid]
    end
  end
=end

  class CONST
    def libjit_compile(function, env)
      klass = function.insn_call_native(:rb_class_of, 0, env.frame.self)
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
      lit = function.const(JIT::Type::OBJECT, self.lit)
      return lit
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
      return self
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
        last = n.head.libjit_compile(function, env)
        n = n.next
      end
      return last
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

  class FOR
    def libjit_compile(function, env)
      # var - an assignment node that gets executed each time through
      # the loop
      # body - the body of the loop
      # iter - the sequence to iterate over
      # 1. compile a nested function from the body of the loop
      # 2. pass this nested function as a parameter to 

      env_ptr = env.address()

      each_signature = JIT::Type.create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::VOID_PTR ])
      each_f = JIT::Function.compile(function.context, each_signature) do |f|
        f.optimization_level = env.optimization_level

        # TODO: not sure if this is needed here?  not sure if it even helps?
        ruby_sourceline = f.ruby_sourceline()
        n = f.const(JIT::Type::INT, self.nd_line)
        f.insn_store_relative(ruby_sourceline, 0, n)

        outer_env_ptr = f.get_param(0)
        inner_env = JIT::NodeCompileEnvironment.from_address(
            f, outer_env_ptr, env.scope.local_names, env.optimization_level)
        recv = self.iter.libjit_compile(f, inner_env)
        id_each = f.const(JIT::Type::ID, :each)
        zero = f.const(JIT::Type::INT, 0)
        result = f.insn_call_native(:rb_funcall, 0, recv, id_each, zero)
        f.insn_return(result)
      end

      body_signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::OBJECT, JIT::Type::VOID_PTR ])
      body_f = JIT::Function.compile(function.context, body_signature) do |f|
        f.optimization_level = env.optimization_level
        value = f.get_param(0)
        outer_env_ptr = f.get_param(1)
        inner_env = JIT::NodeCompileEnvironment.from_address(
            f, outer_env_ptr, env.scope.local_names, env.optimization_level)
        inner_env.scope.local_set(self.var.vid, value)
        if self.body then
          result = self.body.libjit_compile(f, inner_env)
        else
          result = f.const(JIT::Type::OBJECT, nil)
        end
        f.insn_return(result)
      end

      each_c = function.const(JIT::Type::VOID_PTR, each_f.to_closure)
      body_c = function.const(JIT::Type::VOID_PTR, body_f.to_closure)
      result = function.insn_call_native(:rb_iterate, 0, each_c, env_ptr, body_c, env_ptr)
      return result
    end
  end

=begin
  class ITER
    def libjit_compile(function, env)
      # var - an assignment node that gets executed each time through
      # the loop
      # body - the body of the loop
      # iter - the sequence to iterate over
      # 1. compile a nested function from the body of the loop
      # 2. pass this nested function as a parameter to 

      each_signature = JIT::Type.create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::VOID_PTR ])
      each_f = JIT::Function.compile(env.context, each_signature) do |f|
        f.optimization_level = env.optimization_level
        recv = self.iter.libjit_compile(f, env)
        id_each = f.const(JIT::Type::ID, :each)
        zero = f.const(JIT::Type::INT, 0)
        result = f.insn_call_native(:rb_funcall, 0, recv, id_each, zero)
        f.insn_return(result)
      end

      # TODO: handle multiple assignment
      var = function.value(JIT::Type::OBJECT)
      env = env.dup
      env.locals[self.var.vid] = var

      body_signature = JIT::Type::create_signature(
        JIT::ABI::CDECL,
        JIT::Type::OBJECT,
        [ JIT::Type::OBJECT, JIT::Type::VOID_PTR ])
      body_f = JIT::Function.compile(env.context, body_signature) do |f|
        value = f.get_param(0)
        f.insn_store(var, value)
        result = self.body.libjit_compile(f, env)
        f.insn_return(result)
      end

      each_c = function.const(JIT::Type::VOID_PTR, each_f.to_closure)
      body_c = function.const(JIT::Type::VOID_PTR, body_f.to_closure)
      null_ptr = function.const(JIT::Type::VOID_PTR, 0);
      function.insn_call_native(:rb_iterate, 0, each_c, null_ptr, body_c, null_ptr)
    end
  end
=end

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

  class ARRAY
    def libjit_compile(function, env)
      a = self.to_a
      n = function.const(JIT::Type::INT, a.length)
      debug_print_object(function, function.const(JIT::Type::OBJECT, "HERE"))
      ary = function.insn_call_native(:rb_ary_new2, 0, n)
      a.each_with_index do |elem, idx|
        i = function.const(JIT::Type::INT, idx)
        value = elem.libjit_compile(function, env)
        function.insn_call_native(:rb_ary_store, 0, ary, i, value)
      end
      return ary
    end
  end

  class DOT2
    def libjit_compile(function, env)
      range_begin = self.beg.libjit_compile(function, env)
      range_end = self.end.libjit_compile(function, env)
      exclude_end = function.const(JIT::Type::INT, 0)
      return function.insn_call_native(:rb_range_new, 0, range_begin, range_end, exclude_end)
    end
  end

  class DOT3
    def libjit_compile(function, env)
      range_begin = self.beg.libjit_compile(function, env)
      range_end = self.end.libjit_compile(function, env)
      exclude_end = function.const(JIT::Type::INT, 1)
      return function.insn_call_native(:rb_range_new, 0, range_begin, range_end, exclude_end)
    end
  end
end

module JIT
  class NodeCompileFrame
    FrameType = JIT::Type.create_struct([
        JIT::Type::OBJECT, # self
    ])

    def self.from_address(function, address)
      frame = function.insn_load_relative(address, 0, FrameType)
      return self.new(function, frame)
    end

    def initialize(function, frame=nil)
      @function = function
      @frame = frame ? frame : function.value(FrameType)
      @frame_ptr = function.insn_address_of(@frame)
      @self_offset = function.const(JIT::Type::INT, 0)
    end

    def self
      return @function.insn_load_elem(@frame_ptr, @self_offset, JIT::Type::OBJECT)
      # return @self
    end

    def self=(value)
      @function.insn_store_elem(@frame_ptr, @self_offset, value)
      # @self = value
    end

    def address
      return @frame_ptr
    end
  end

  class NodeLocalVariable
    def initialize(function, name)
      @function = function
      @name = name
      @addressable = false
    end

    def set(value)
      if @addressable then
        @function.insn_store_relative(@array, @offset, value)
      else
        if @value then
          @function.insn_store(@value, value)
        else
          @value = value
        end
      end
    end

    def get
      if @addressable then
        return @function.insn_load_relative(@array, @offset, JIT::Type::OBJECT)
      else
        return @value
      end
    end

    def set_addressable(array, offset)
      @addressable = true
      @array = array
      @offset = offset
      # TODO: assert that @value is not addressable
      if defined?(@value) then
        @function.insn_store_relative(@array, @offset, @value)
      end
    end
  end

  class NodeCompileScope
    attr_reader :scope_type
    attr_reader :scope
    attr_reader :local_names

    # TODO: This function isn't right
    def self.from_address(function, address, local_names)
      scope_type = JIT::Type.create_struct(
          [ JIT::Type::OBJECT ] * local_names.size
      )
      # scope = function.insn_load_relative(function, address, 0, scope_type)
      locals = {}
      local_names.each_with_index do |name, idx|
        locals[name] = NodeLocalVariable.new(
            function,
            name)
        locals[name].set_addressable(address, scope_type.get_offset(idx))
      end
      return self.new(function, local_names, locals)
    end

    def initialize(function, local_names, locals=nil)
      @function = function
      @scope_type = JIT::Type.create_struct(
          [ JIT::Type::OBJECT ] * local_names.size
      )
      @scope = function.value(@scope_type)

      @local_names = local_names

      if locals then
        @locals = locals
      else
        @locals = {}
        local_names.each do |name|
          @locals[name] = NodeLocalVariable.new(
              function,
              name)
        end
      end
    end

    def local_set(vid, value)
      @locals[vid].set(value)
    end

    def local_get(vid)
      return @locals[vid].get()
    end

    def address
      @scope_ptr = @function.insn_address_of(@scope)
      @local_names.each_with_index do |name, idx|
        offset = @scope_type.get_offset(idx)
        @locals[name].set_addressable(@scope_ptr, offset)
      end
      return @scope_ptr
    end
  end

  class NodeCompileEnvironment
    attr_reader :frame
    attr_reader :scope
    attr_accessor :optimization_level

    def initialize(function, optimization_level, frame, scope)
      @function = function
      @optimization_level = optimization_level
      @frame = frame
      @scope = scope
      @scope_stack = []
    end

    # def push_scope
    #   @scope_stack.push(@scope)
    #   @scope = scope.dup
    # end

    def address
      env_type = JIT::Type.create_struct([ JIT::Type::VOID_PTR, JIT::Type::VOID_PTR ])
      env_ptr = @function.insn_address_of(@function.value(env_type))
      @function.insn_store_relative(env_ptr, 0, self.frame.address)
      @function.insn_store_relative(env_ptr, 4, self.scope.address)
      return env_ptr
    end

    def self.from_address(function, address, local_names, optimization_level)
      frame_ptr = function.insn_load_relative(address, 0, JIT::Type::VOID_PTR)
      scope_ptr = function.insn_load_relative(address, 4, JIT::Type::VOID_PTR)
      frame = JIT::NodeCompileFrame.from_address(function, frame_ptr)
      scope = JIT::NodeCompileScope.from_address(function, scope_ptr, local_names) # TODO
      env = JIT::NodeCompileEnvironment.new(function, optimization_level, frame, scope)
    end
  end
end

class Method
  def libjit_compile(optimization_level=2)
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
        f.optimization_level = optimization_level

        frame = JIT::NodeCompileFrame.new(
            f)
        scope = JIT::NodeCompileScope.new(
            f,
            self.body.tbl || [])
        env = JIT::NodeCompileEnvironment.new(
            f,
            optimization_level,
            frame,
            scope)

        if self.arity >= 0 then
          # all arguments required for this method
          env.frame.self = f.get_param(0)
          msig.arg_names.each_with_index do |arg_name, idx|
            # TODO: how to deal with default values?
            env.scope.local_set(arg_name,  f.get_param(idx+1))
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
          env.frame.self = f.get_param(2)

          msig.arg_names.each_with_index do |arg_name, idx|
            if idx < msig.arg_names.size - optional_args.size then
              # TODO: use insn_load_elem?
              env.local_set(arg_name, f.insn_load_relative(argv, idx*4, JIT::Type::OBJECT))
            else
              var = f.value(JIT::Type::OBJECT)
              env.scope.local_set(arg_name, var)
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

        result = self.body.libjit_compile(f, env)
        if not Node::RETURN === result then
          f.insn_return(result)
        end
        # puts f
        puts "About to compile..."
      end

      return function
    end
  end
end

if __FILE__ == $0 then

  require 'nodepp'

=begin
def gcd2(x, y)
  while x != y do
    puts x, y
    if x < y
      y -= x
    else
      x -= y
    end
  end
  return x
end
=end

def array_access(n=1)
   x = Array.new(n)
   y = Array.new(n, 0)

   for i in 0...n
      # x[i] = i + 1
     puts "i=#{i}"
   end

   # for k in 0..999
   #    (n-1).step(0,-1) do |i|
   #       y[i] = y.at(i) + x.at(i)
   #    end
   # end
end

m = method(:array_access)
# pp m.body
f = m.libjit_compile
puts "Compiled"
# puts f
p f.apply(self, 10)

end
