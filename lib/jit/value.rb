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

    def store(value)
      self.function.insn_store(self, value)
    end

    def address
      return self.function.insn_address_of(self)
    end

    def +(rhs)
      return self.function.insn_add(self, rhs)
    end

    def -(rhs)
      return self.function.insn_sub(self, rhs)
    end

    def *(rhs)
      return self.function.insn_mul(self, rhs)
    end

    def /(rhs)
      return self.function.insn_div(self, rhs)
    end

    def -@()
      return self.function.const(self.type, 0) - self
    end

    def %(rhs)
      return self.function.insn_rem(self, rhs)
    end

    def &(rhs)
      return self.function.insn_and(self, rhs)
    end

    def |(rhs)
      return self.function.insn_or(self, rhs)
    end

    def ^(rhs)
      return self.function.insn_xor(self, rhs)
    end

    def <(rhs)
      return self.function.insn_lt(self, rhs)
    end

    def >(rhs)
      return self.function.insn_gt(self, rhs)
    end

    def ==(rhs)
      return self.function.insn_eq(self, rhs)
    end

    def neq(rhs)
      return self.function.insn_ne(self, rhs)
    end

    def <=(rhs)
      return self.function.insn_le(self, rhs)
    end

    def >=(rhs)
      return self.function.insn_ge(self, rhs)
    end

    def <<(rhs)
      return self.function.insn_shl(self, rhs)
    end

    def >>(rhs)
      return self.function.insn_shr(self, rhs)
    end

    def ~()
      return self.function.insn_not(self)
    end
  end
end

