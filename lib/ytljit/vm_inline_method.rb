module YTLJit
  module VM
    module ArithmeticOperationUtil
      include AbsArch
      def decide_type_core_local(tlist, sig, local_cache = {})
        tlist = tlist.select {|e| e.class != RubyType::DefaultType0 }
        if tlist.size < 2 then
          return decide_type_core(tlist, local_cache)
        end
        aele = @arguments[3].decide_type_once(sig)
        p aele
        p @arguments[3].func.name
        if tlist.include?(aele) then
          aele
        else
          RubyType::DefaultType0.new
        end
      end
      
      def decide_type_once(sig, local_cache = {})
        if local_cache[self] then
          return local_cache[self] 
        end
        
        if @type.equal?(nil) or @type.is_a?(RubyType::DefaultType0) then
          tlist = type_list(sig).flatten.uniq
          @type = decide_type_core_local(tlist, sig, local_cache)
        else
          @type
        end
        
        @type
      end

      def gen_arithmetic_operation(context, inst, tempreg, resreg)
        context.start_using_reg(tempreg)
        context = gen_eval_self(context)
        context.ret_node.type = nil
        rtype = context.ret_node.decide_type_once(context.to_signature)
        context = rtype.gen_unboxing(context)
        asm = context.assembler
        if context.ret_reg.using(tempreg) then
          asm.with_retry do
            asm.mov(TMPR, context.ret_reg)
          end
          context.end_using_reg(context.ret_reg)
          asm.with_retry do
            asm.mov(tempreg, TMPR)
          end
        else
          asm.with_retry do
            asm.mov(tempreg, context.ret_reg)
          end
          context.end_using_reg(context.ret_reg)
        end
        context.set_reg_content(tempreg, context.ret_node)
        
        # @argunents[1] is block
        # @argunents[2] is self
        # @arguments[3] is other
        aele = @arguments[3]
        context = aele.compile(context)
        context.ret_node.type = nil
        rtype = context.ret_node.decide_type_once(context.to_signature)
        context = rtype.gen_unboxing(context)
          
        asm = context.assembler
        if block_given? then
          yield(context)
        else
          asm.with_retry do
            # default code
            if context.ret_reg.using(tempreg) then
              asm.mov(TMPR, context.ret_reg)
              context.end_using_reg(context.ret_reg)
              asm.send(inst, tempreg, TMPR)
            else
              asm.send(inst, tempreg, context.ret_reg)
              context.end_using_reg(context.ret_reg)
            end
            asm.mov(resreg, tempreg)
          end
        end

        context.end_using_reg(tempreg)

        context.ret_node = self
        context.ret_reg = resreg
        
        decide_type_once(context.to_signature)
        if @type.boxed then
          context = @type.gen_boxing(context)
        end
        
        context
      end
    end

    module CompareOperationUtil
      def gen_compare_operation(context, cinst, sinst, 
                                tempreg, tempreg2, resreg)
        context.start_using_reg(tempreg)
        asm = context.assembler
        asm.with_retry do
          asm.mov(tempreg, context.ret_reg)
        end
        context.set_reg_content(tempreg, context.ret_node)
        context.set_reg_content(tempreg, context.ret_node)
        
        # @arguments[1] is block
        # @arguments[2] is self
        # @arguments[3] is other arg
        aele = @arguments[3]
        context = aele.compile(context)
        context.ret_node.type = nil
        rtype = context.ret_node.decide_type_once(context.to_signature)
        context = rtype.gen_unboxing(context)
          
        asm = context.assembler
        asm.with_retry do
          if context.ret_reg != tempreg2 then
            asm.mov(tempreg2, context.ret_reg)
          end
          asm.send(cinst, tempreg2, tempreg)
          asm.send(sinst, resreg)
          asm.add(resreg, resreg)
        end
        context.end_using_reg(tempreg)
        
        context.ret_node = self
        context.ret_reg = resreg
        
        decide_type_once(context.to_signature)
        if @type.boxed then
          context = @type.gen_boxing(context)
        end
        
        context
      end
    end
  end
end
