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

    def unless(cond, end_label = Label.new, &block)
      true_label = Label.new
      insn_branch_if(cond, true_label)
      block.call
      insn_branch(end_label)
      insn_label(true_label)
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

      def elsunless(cond, &block)
        return @function.unless(cond, @end_label, &block)
      end

      def end
        @function.insn_label(@end_label)
      end
    end

    # Usage:
    #   until(proc { <condition> }) {
    #   } .end
    def until(cond, &block)
      start_label = Label.new
      done_label = Label.new
      insn_label(start_label)
      insn_branch_if(cond.call, done_label)
      loop = Loop.new(self, start_label, done_label)
      block.call(loop)
      insn_branch(start_label)
      insn_label(done_label)
      return loop
    end

    # Usage:
    #   while(proc { <condition> }) {
    #   } .end
    def while(cond, &block)
      start_label = Label.new
      done_label = Label.new
      insn_label(start_label)
      insn_branch_if_not(cond.call, done_label)
      loop = Loop.new(self, start_label, done_label)
      block.call(loop)
      insn_branch(start_label)
      insn_label(done_label)
      return loop
    end

    class Loop
      def initialize(function, start_label, done_label)
        @function = function
        @redo_label = start_label
        @done_label = done_label
      end

      def end
      end

      def break
        @function.insn_branch(@done_label)
      end

      def redo
        @function.insn_branch(@redo_label)
      end

      def redo_from_here
        @redo_label = JIT::Label.new
        @function.insn_label(@redo_label)
      end
    end
  end
end

