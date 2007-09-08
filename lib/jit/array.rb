require 'jit'
require 'jit/value'

module JIT
  class Array < JIT::Type
    def self.new(type, length)
      type = self.create_struct([ type ] * length)
      type.instance_eval do
        @type = type
        @length = length
      end
      return type
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
      def self.wrap(struct, function, ptr)
        pointer_type = JIT::Type.create_pointer(struct)
        value = self.new_value(function, pointer_type)
        value.store(ptr)
        value.set_stuff(struct, function, ptr)
        value.instance_eval do
          @struct = struct
          @function = function
          @ptr = ptr
        end
        return value
      end

      def [](index)
        @function.insn_load_relative(
            @ptr,
            @struct.offset_of(index),
            @struct.type_of(index))
      end

      def []=(index, value)
        @function.insn_store_relative(
            @ptr,
            @struct.offset_of(index),
            value)
      end
    end
  end
end

if __FILE__ == $0 then
  a = JIT::Array.new()
end

