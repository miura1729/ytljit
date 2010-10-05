module YTLJit
  module VM
    module ArithmeticOperationUtil
      def gen_arithmetic_operation(context, inst, tempreg, resreg)
        context.start_using_reg(tempreg)
        asm = context.assembler
        asm.with_retry do
          asm.mov(tempreg, context.ret_reg)
        end
        context.set_reg_content(tempreg, context.ret_node)
        
        # @argunemnts[1] is block
        # @argunemnts[2] is self
        # eval 2nd, 3thr, ... arguments and added
        @arguments[3..-1].each do |aele|
          context = aele.compile(context)
          context.ret_node.decide_type_once(context.to_key)
          rtype = context.ret_node.type
          context = rtype.gen_unboxing(context)
          
          asm = context.assembler
          asm.with_retry do
            asm.send(inst, tempreg, context.ret_reg)
          end
        end

        asm.with_retry do
          asm.mov(resreg, tempreg)
        end
        context.end_using_reg(tempreg)
        
        context.ret_node = self
        context.ret_reg = resreg
        
        decide_type_once(context.to_key)
        if type.boxed then
          context = type.gen_boxing(context)
        end
        
        context
      end
    end

    module CompareOperationUtil
      def gen_compare_operation(context, inst, tempreg, resreg)
        context.start_using_reg(tempreg)
        asm = context.assembler
        asm.with_retry do
          asm.mov(tempreg, context.ret_reg)
        end
        context.set_reg_content(tempreg, context.ret_node)
        
        # @argunemnts[1] is block
        # @argunemnts[2] is self
        # eval 2nd arguments and compare
        aele = @arguments[3]
        context = aele.compile(context)
        context.ret_node.decide_type_once(context.to_key)
        rtype = context.ret_node.type
        context = rtype.gen_unboxing(context)
          
        asm = context.assembler
        asm.with_retry do
          if context.ret_reg != resreg then
            asm.mov(resreg, context.ret_reg)
          end
          asm.cmp(resreg, tempreg)
          asm.send(inst, resreg)
          asm.add(resreg, resreg)
        end
        context.end_using_reg(tempreg)
        
        context.ret_node = self
        context.ret_reg = resreg
        
        decide_type_once(context.to_key)
        if type.boxed then
          context = type.gen_boxing(context)
        end
        
        context
      end
    end
  end
end
