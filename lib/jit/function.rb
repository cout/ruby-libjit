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
    #   } .end
    #
    # Caution: if you omit end, then the generated code will have
    # undefined behavior, but there will be no warning generated.
    def if(cond, end_label = Label.new, &block)
      false_label = Label.new
      insn_branch_if_not(cond, false_label)
      block.call
      insn_branch(end_label)
      insn_label(false_label)
      return If.new(self, end_label)
    end

    class If
      def initialize(function, end_label)
        @function = function
        @end_label = end_label
      end

      def else(&block)
        block.call
        return self
      end

      def elsif(cond, &block)
        return @function.if(cond, @end_label, &block)
      end

      def end
        @function.insn_label(@end_label)
      end
    end
  end
end

