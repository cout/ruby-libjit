require 'jit'

module JIT
  class Struct < JIT::Type
    def self.new(*members)
      member_names = members.map { |m| m[0].to_s.intern }
      member_types = members.map { |m| m[1] }
      type = self.create_struct(member_types)
      type.instance_eval do
        @members = members
        @member_names = member_names
        @member_types = member_types
      end
      return type
    end

    def members
      return @member_names
    end

    def wrap(function, ptr)
      return Instance.new(self, function, ptr)
    end

    def create(function)
      instance = function.value(self)
      ptr = function.insn_address_of(instance)
      return wrap(function, ptr)
    end

    def offset_of(name)
      name = (Symbol === name) ? name : name.to_s.intern
      return self.get_offset(@member_names.index(name))
    end

    def type_of(name)
      name = (Symbol === name) ? name : name.to_s.intern
      return @member_types[@member_names.index(name)]
    end

    class Instance
      attr_reader :ptr

      def initialize(struct, function, ptr)
        @struct = struct
        @function = function
        @ptr = ptr

        mod = Module.new do
          struct.members.each do |name|
            define_method("#{name}") do
              return self[name]
            end

            define_method("#{name}=") do |value|
              return self[name] = value
            end
          end
        end

        extend(mod)
      end

      def [](member_name)
        @function.insn_load_relative(
            @ptr,
            @struct.offset_of(member_name),
            @struct.type_of(member_name))
      end

      def []=(member_name, value)
        @function.insn_store_relative(
            @ptr,
            @struct.offset_of(member_name),
            value)
      end

      def members
        return @struct.members
      end
    end
  end
end

if __FILE__ == $0 then
  s = JIT::Struct.new()
  p s
end

