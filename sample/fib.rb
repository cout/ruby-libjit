require 'jit'

fib = nil
JIT::Context.build do |context|
  signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::INT,
      [ JIT::Type::INT ])
  fib = JIT::Function.compile(context, signature) do |f|
    n = f.param(0)

    zero = f.const(JIT::Type::INT, 0)
    one = f.const(JIT::Type::INT, 1)

    a = f.value(JIT::Type::INT); a.store(zero)
    b = f.value(JIT::Type::INT); b.store(one)
    c = f.value(JIT::Type::INT); c.store(one)

    i = f.value(JIT::Type::INT); i.store(zero)

    f.while(proc { i < n }) {
      c.store(a + b)
      a.store(b)
      b.store(c)
      i.store(i + one)
    }.end

    f.return(c)
  end
end

values = (0...10).collect { |x| fib.apply(x) }
p values #=> [1, 1, 2, 3, 5, 8, 13, 21, 34, 55]

