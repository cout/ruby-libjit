require 'jit'

module JIT
  class Value
    module UNINITIALIZED; end

    def self.new(function, type, value=UNINITIALIZED)
      # TODO: Not sure if I like this...
      if value == UNINITIALIZED then
        return function.value(type)
      else
        return function.const(type, value)
      end
    end

    def store(function, value)
      function.insn_store(self, value)
    end

    def is_fixnum
      fixnum_flag = self.function.const(JIT::Type::INT, 1)
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

