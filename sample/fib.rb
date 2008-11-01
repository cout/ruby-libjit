require 'jit'

fib = nil
JIT::Context.build do |context|
  signature = JIT::Type.create_signature(
      JIT::ABI::CDECL,
      JIT::Type::INT,
      [ JIT::Type::INT ])
  fib = JIT::Function.compile(context, signature) do |f|
    n = f.param(0)

    a = f.value(JIT::Type::INT); a.store(0)
    b = f.value(JIT::Type::INT); b.store(1)
    c = f.value(JIT::Type::INT); c.store(1)

    i = f.value(JIT::Type::INT); i.store(0)

    f.while(proc { i < n }) {
      c.store(a + b)
      a.store(b)
      b.store(c)
      i.store(i + 1)
    }.end

    f.return(c)
  end
end

values = (0...10).collect { |x| fib.apply(x) }
p values #=> [1, 1, 2, 3, 5, 8, 13, 21, 34, 55]

