require 'jit'
require 'jit/value'

module JIT
  class Array < JIT::Type
    attr_reader :type
    attr_reader :length

    def self.new(type, length)
      array = self.create_struct([ type ] * length)
      array.instance_eval do
        @type = type
        @length = length
      end
      return array
    end

    def wrap(function, ptr)
      return Instance.wrap(self, function, ptr)
    end

    def create(function)
      instance = function.value(self)
      ptr = function.insn_address_of(instance)
      return wrap(function, ptr)
    end

    def offset_of(index)
      return self.get_offset(index)
    end

    def type_of(index)
      return @type
    end

    class Instance < JIT::Value
      attr_reader :array_type
      attr_reader :type
      attr_reader :ptr

      # TODO: This breaks code below?
      # attr_reader :function

      def self.wrap(array_type, function, ptr)
        pointer_type = JIT::Type.create_pointer(array_type)
        value = self.new_value(function, pointer_type)
        value.store(ptr)
        value.instance_eval do
          @array_type = array_type
          @type = array_type.type
          @function = function
          @ptr = ptr
        end
        return value
      end

      def [](index)
        @function.insn_load_relative(
            @ptr,
            @array_type.offset_of(index),
            @array_type.type_of(index))
      end

      def []=(index, value)
        @function.insn_store_relative(
            @ptr,
            @array_type.offset_of(index),
            value)
      end
    end
  end
end

if __FILE__ == $0 then
  a = JIT::Array.new()
end

