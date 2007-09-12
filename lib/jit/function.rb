require 'jit'

module JIT
  class Function
    # An abstraction for conditionals.  Use it like this:
    #
    #   if(condition) {
    #     # condition is true
    #   } .elsif(condition2) {
    #     # condition2 is true
    #   } .else {
    #     # condition1 and condition2 are false
    #   }
    #
    def if(cond, end_label = Label.new, &block)
      false_label = Label.new
      insn_branch_if_not(cond, false_label)
      block.call
      insn_branch(end_label)
      insn_label(false_label)
      return Else.new(self, end_label)
    end

    class Else
      def initialize(function, end_label)
        @function = function
        @end_label = end_label
      end

      def else(&block)
        block.call
        @function.insn_label(@end_label)
      end

      def elsif(cond, &block)
        new_else = @function.if(cond, @end_label, &block)
        return new_else
      end
    end
  end
end

