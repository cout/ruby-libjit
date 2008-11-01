require 'jit'

module JIT
  class Value
    module UNINITIALIZED; end

    # Create a new JIT::Value.  If value is specified, the value will be
    # variable, otherwise it will be a constant with the given value.
    #
    # +function+:: The function to which this value will belong.
    # +type+::     The type of the new value.
    # +value+:     The value to use, if this is a constant.
    #
    def self.new(function, type, value=UNINITIALIZED)
      # TODO: Not sure if I like this...
      if value == UNINITIALIZED then
        return function.value(type)
      else
        return function.const(type, value)
      end
    end

    # Assign +value+ to this JIT::Value.
    #
    # +value+:: The value to assign.
    #
    def store(value)
      self.function.insn_store(self, value)
    end

    # Return the address of this value.
    def address
      return self.function.insn_address_of(self)
    end

    # Add this value to another and return the result.
    #
    # +rhs+:: The right hand side of the addition operator.
    #
    def +(rhs)
      return self.function.insn_add(self, rhs)
    end

    # Subtract another value from this one and return the result.
    #
    # +rhs+:: The right hand side of the subtraction operator.
    #
    def -(rhs)
      return self.function.insn_sub(self, rhs)
    end

    # Multiply this value by another and return the result.
    #
    # +rhs+:: The right hand side of the multiplication operator.
    #
    def *(rhs)
      return self.function.insn_mul(self, rhs)
    end

    # Divide this value by another and return the quotient.
    #
    # +rhs+:: The right hand side of the division operator.
    #
    def /(rhs)
      return self.function.insn_div(self, rhs)
    end

    # Return the additive inverse (negation) of this value.
    def -@()
      return self.function.const(self.type, 0) - self
    end

    # Divide this value by another and return the remainder.
    #
    # +rhs+:: The right hand side of the modulus operator.
    #
    def %(rhs)
      return self.function.insn_rem(self, rhs)
    end

    # Perform a bitwise and between this value and another.
    #
    # +rhs+:: The right hand side of the operator.
    #
    def &(rhs)
      return self.function.insn_and(self, rhs)
    end

    # Perform a bitwise or between this value and another.
    #
    # +rhs+:: The right hand side of the operator.
    #
    def |(rhs)
      return self.function.insn_or(self, rhs)
    end

    # Perform a bitwise xor between this value and another.
    #
    # +rhs+:: The right hand side of the operator.
    #
    def ^(rhs)
      return self.function.insn_xor(self, rhs)
    end

    # Compare this value to another, returning 1 if the left hand is
    # less than the right hand side or 0 otherwise.
    #
    # +rhs+:: The right hand side of the comparison.
    #
    def <(rhs)
      return self.function.insn_lt(self, rhs)
    end

    # Compare this value to another, returning 1 if the left hand is
    # greater than the right hand side or 0 otherwise.
    #
    # +rhs+:: The right hand side of the comparison.
    #
    def >(rhs)
      return self.function.insn_gt(self, rhs)
    end

    # Compare this value to another, returning 1 if the left hand is
    # equal to the right hand side or 0 otherwise.
    #
    # +rhs+:: The right hand side of the comparison.
    #
    def ==(rhs)
      return self.function.insn_eq(self, rhs)
    end

    # Compare this value to another, returning 1 if the left hand is
    # not equal to the right hand side or 0 otherwise.
    #
    # +rhs+:: The right hand side of the comparison.
    #
    def neq(rhs)
      return self.function.insn_ne(self, rhs)
    end

    # Compare this value to another, returning 1 if the left hand is
    # less than or equal to the right hand side or 0 otherwise.
    #
    # +rhs+:: The right hand side of the comparison.
    #
    def <=(rhs)
      return self.function.insn_le(self, rhs)
    end

    # Compare this value to another, returning 1 if the left hand is
    # greater than or equal to the right hand side or 0 otherwise.
    #
    # +rhs+:: The right hand side of the comparison.
    #
    def >=(rhs)
      return self.function.insn_ge(self, rhs)
    end

    # Shift this value left by the given number of bits.
    #
    # +rhs+:: The number of bits to shift by.
    #
    def <<(rhs)
      return self.function.insn_shl(self, rhs)
    end

    # Shift this value right by the given number of bits.
    #
    # +rhs+:: The number of bits to shift by.
    #
    def >>(rhs)
      return self.function.insn_shr(self, rhs)
    end

    # Return the logical inverse of this value.
    def ~()
      return self.function.insn_not(self)
    end
  end
end

