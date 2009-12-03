require 'jit'

multiply = nil
JIT::Context.build do |context|
  multiply = context.compile_function([:INT, :INT] => :INT) do |f|
    lhs = f.get_param(0)
    rhs = f.get_param(1)
    result = f.insn_mul(lhs, rhs)
    f.insn_return(result)
  end
end

p multiply.apply(6, 7) #=> 42
