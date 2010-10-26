module YTLJit
  module Runtime
    include InternalRubyType
    # Format of header
    #
    #     size of object
    #   xxxxxxxxxxxxxxxxxxxFEUTFRM
    #
    ADDRESS = AsmType::MACHINE_WORD
    YTLObject = AsmType::Struct.new(
                  VALUE, :header, 
                  ADDRESS, :traverse_func,
                  AsmType::Array.new(VALUE, 0), :body
                )
  end
end

    
