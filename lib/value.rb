require 'jit'

module JIT
  class Value
    module UNINITIALIZED; end

    def self.new(function, value=UNINITIALIZED)
      if value == UNINITIALIZED then
        return function.value
      else
        return function.value(value)
      end
    end

    def +(rhs)
      return self.function.insn_add(self, rhs)
    end
  end
end

