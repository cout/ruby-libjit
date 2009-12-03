require 'jit'

multiply = JIT::Function.build([:INT, :INT] => :INT) do |f|
  lhs = f.get_param(0)
  rhs = f.get_param(1)
  f.return(lhs * rhs)
end

p multiply.apply(6, 7) #=> 42
