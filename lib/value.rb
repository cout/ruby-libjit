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

    def is_fixnum
      fixnum_flag = self.function.value(JIT::Type::INT, 1)
      return self.function.insn_and(self, fixnum_flag)
    end

    def +(rhs)
      return self.function.insn_add(self, rhs)
    end

    def -(rhs)
      return self.function.insn_sub(self, rhs)
    end

    def &(rhs)
      return self.function.insn_and(self, rhs)
    end

    def <(rhs)
      return self.function.insn_lt(self, rhs)
    end

    def ==(rhs)
      return self.function.insn_eq(self, rhs)
    end
  end
end
