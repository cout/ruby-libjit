module JIT
  class Type
    # Create a new signature.
    #
    # call-seq:
    #   jit = JIT::Type.create_signature(abi, return_type, array_of_param_types)
    #   jit = JIT::Type.create_signature(array_of_param_types => return_type)
    #   jit = JIT::Type.create_signature(array_of_param_types => return_type, :abi => abi)
    def self.create_signature(*args)
      if args.size == 1 then
        h = args[0]
        return_type = nil
        param_types = nil
        abi = :CDECL
        h.each do |k, v|
          if k == :abi then
            abi = v
          else
            param_types = k
            return_type = v
          end
        end

        if return_type.nil? or param_types.nil? then
          raise ArgumentError, "Missing return_type and/or param types"
        end

        return self._create_signature(abi, return_type, param_types)

      elsif args.size == 3 then
        return self._create_signature(args[0], args[1], args[2])

      else
        raise ArgumentError, "Wrong number of arguments (expected 3)"
      end
    end
  end
end
