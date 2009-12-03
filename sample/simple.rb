require 'jit'

multiply = JIT::Function.build([:INT, :INT] => :INT) do |f|
  lhs = f.param(0)
  rhs = f.param(1)
  f.return(lhs * rhs)
end

p multiply.apply(6, 7) #=> 42
