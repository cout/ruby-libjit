require 'jit'

function = nil
JIT::Context.build do |context|
  function = context.compile_function([:INT] => :INT) do |f|
    value = f.get_param(0)
    f.insn_return(value)
  end
end

p function.apply(42) #=> 42
