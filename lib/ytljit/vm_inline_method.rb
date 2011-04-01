module YTLJit
  module VM
    module ArithmeticOperationUtil
      include AbsArch
=begin
      def decide_type_core_local(tlist, sig, local_cache = {})
        tlist = tlist.select {|e| e.class != RubyType::DefaultType0 }
        if tlist.size < 2 then
          return decide_type_core(tlist, local_cache)
        end
        aele = @arguments[3].decide_type_once(sig)
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
=end

      def gen_inst_with_conversion(context, dst, inst)
        asm = context.assembler
        src = context.ret_reg
        if dst.is_a?(OpRegXMM) then
          # Float
          if src.is_a?(OpRegistor) and
              !src.is_a?(OpRegXMM) then
            asm.with_retry do
              asm.cvtsi2sd(XMM0, src)
            end
            context.end_using_reg(src)
            asm.with_retry do
              asm.send(inst, dst, XMM0)
            end
          elsif src.using(dst) then
            asm.with_retry do
              asm.mov(XMM0, src)
            end
            context.end_using_reg(src)
            asm.with_retry do
              asm.send(inst, dst, XMM0)
            end
          elsif src.is_a?(OpImmidiateMachineWord) then
            asm.with_retry do
              asm.mov(TMPR, src)
            end
            context.end_using_reg(src)
            asm.with_retry do
              asm.cvtsi2sd(XMM0, TMPR)
              asm.send(inst, dst, XMM0)
            end
          else
            asm.with_retry do
              asm.send(inst, dst, src)
            end
            context.end_using_reg(src)
          end
        else
          # Fixnum
          if src.using(dst) then
            asm.with_retry do
              asm.mov(TMPR, src)
            end
            context.end_using_reg(src)
            asm.with_retry do
              asm.send(inst, dst, TMPR)
            end
          else
            asm.with_retry do
              asm.send(inst, dst, src)
            end
            context.end_using_reg(src)
          end
        end
      end

      def gen_arithmetic_operation(context, inst, tempreg, resreg)
        context.start_using_reg(tempreg)
        context = gen_eval_self(context)
        context.ret_node.type = nil
        rtype = context.ret_node.decide_type_once(context.to_signature)
        context = rtype.gen_unboxing(context)
        gen_inst_with_conversion(context, tempreg, :mov)
        context.set_reg_content(tempreg, context.ret_node)
        
        # @argunents[1] is block
        # @argunents[2] is self
        # @arguments[3] is other
        aele = @arguments[3]
        context = aele.compile(context)
        context.ret_node.type = nil
        rtype = context.ret_node.decide_type_once(context.to_signature)
        context = rtype.gen_unboxing(context)
          
        if block_given? then
          yield(context)
        else
          # default code
          gen_inst_with_conversion(context, tempreg, inst)
          asm = context.assembler
          asm.with_retry do
            asm.mov(resreg, tempreg)
          end
        end

        context.end_using_reg(tempreg)

        context.ret_node = self
        context.ret_reg = resreg
        
        decide_type_once(context.to_signature)
        if @type.boxed then
          context = @type.to_unbox.gen_boxing(context)
        end
        
        context
      end
    end

    module CompareOperationUtil
      def gen_compare_operation(context, cinst, sinst, 
                                tempreg, tempreg2, resreg, dounbox = true)
        context.start_using_reg(tempreg)
        asm = context.assembler
        asm.with_retry do
          asm.mov(tempreg, context.ret_reg)
        end
        context.set_reg_content(tempreg, context.ret_node)
        
        # @arguments[1] is block
        # @arguments[2] is self
        # @arguments[3] is other arg
        aele = @arguments[3]
        context = aele.compile(context)
        context.ret_node.type = nil
        rtype = context.ret_node.decide_type_once(context.to_signature)
        if dounbox then
          context = rtype.gen_unboxing(context)
        end
          
        asm = context.assembler
        asm.with_retry do
          if context.ret_reg != tempreg2 then
            asm.mov(tempreg2, context.ret_reg)
          end
          context.set_reg_content(tempreg2, context.ret_node)
          asm.send(cinst, tempreg2, tempreg)
          asm.send(sinst, resreg)
          asm.add(resreg, resreg)
          context.set_reg_content(resreg, context.ret_node)
        end
        context.end_using_reg(tempreg)
        
        context.ret_node = self
        context.ret_reg = resreg
        
        decide_type_once(context.to_signature)
        
        context
      end
    end

    module UnboxedArrayUtil
      include AbsArch
      def gen_ref_element(context, slf, idx)
        context.start_using_reg(TMPR2)
        context = slf.compile(context)
        asm = context.assembler
        asm.with_retry do
          asm.mov(TMPR2, context.ret_reg)
        end
        if idx.is_a?(Fixnum) then
          idxval = idx
        else
          context = idx.compile(context)
          idxval = context.ret_reg
        end
        asm.with_retry do
          if idxval.is_a?(Fixnum) then
            asm.mov(TMPR, idxval * 8)
          elsif idxval.is_a?(OpImmidiate)
            asm.mov(TMPR, idxval.value * 8)
          else
            if idxval != TMPR then
              asm.mov(TMPR, idxval)
            end
            asm.add(TMPR, TMPR) # * 2
            asm.add(TMPR, TMPR) # * 4
            asm.add(TMPR, TMPR) # * 8
          end
          asm.add(TMPR2, TMPR)
          asm.mov(RETR, INDIRECT_TMPR2)
        end
        
        context.end_using_reg(TMPR2)
        context.ret_reg = RETR
        context.ret_node = self

        context
      end
        
      def gen_set_element(context, slf, idx, val)
        context.start_using_reg(TMPR2)

        asm = context.assembler
        if slf then
          context = slf.compile(context)
          asm.with_retry do
            asm.mov(TMPR2, context.ret_reg)
          end
        end
        if idx.is_a?(Fixnum) then
          idxval = idx
        else
          context = idx.compile(context)
          idxval = context.ret_reg
        end

        asm.with_retry do
          if idxval.is_a?(Fixnum) then
            asm.mov(TMPR, idxval * 8)
          elsif idxval.is_a?(OpImmidiate)
            asm.mov(TMPR, idxval.value * 8)
          else
            asm.mov(TMPR, idxval)
            asm.add(TMPR, TMPR) # * 2
            asm.add(TMPR, TMPR) # * 4
            asm.add(TMPR, TMPR) # * 8
          end
          asm.add(TMPR2, TMPR)
        end
        context = val.compile(context)
        rtype = val.decide_type_once(context.to_signature)
        if rtype.boxed then
          context = rtype.gen_unboxing(context)
        end

        asm.with_retry do
          if context.ret_reg != RETR then
            asm.mov(RETR, context.ret_reg)
          end
          asm.mov(INDIRECT_TMPR2, RETR)
        end
        
        context.end_using_reg(TMPR2)
        context.ret_reg = RETR
        context.ret_node = self
        context
      end
    end
  end
end
