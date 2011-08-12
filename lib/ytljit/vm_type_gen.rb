module YTLJit
  module VM
    module TypeCodeGen
      module DefaultTypeCodeGen
        def instance
          self
        end

        def init_type
        end

        def have_element?
          false
        end

        # Can represent nil by this format
        def include_nil?
          true
        end

        def gen_boxing(context)
          context
        end

        def gen_unboxing(context)
          context
        end

        def gen_copy(context)
          context
        end

        def inspect
          "{ #{boxed ? "BOXED" : "UNBOXED"} #{@ruby_type}}"
        end

        def copy_type
          # Do not copy. It is immutable
          self
        end
      end

      module FixnumTypeUnboxedCodeGen
        include AbsArch
        include CommonCodeGen

        def include_nil?
          false
        end

        def gen_boxing(context)
          asm = context.assembler
          val = context.ret_reg
          vnode = context.ret_node
          asm.with_retry do
            if val != TMPR then
              asm.mov(TMPR, val)
            end
            asm.add(TMPR, TMPR)
            asm.add(TMPR, OpImmidiate8.new(1))
          end

          context.set_reg_content(TMPR, vnode)
          context.ret_reg = TMPR
          context
        end

        def gen_unboxing(context)
          context
        end
      end

      module FixnumTypeBoxedCodeGen
        include AbsArch
        include CommonCodeGen

        def gen_boxing(context)
          context
        end
        
        def gen_unboxing(context)
          asm = context.assembler
          val = context.ret_reg
          vnode = context.ret_node
          asm.with_retry do
            if val != TMPR then
              asm.mov(TMPR, val)
            end
            asm.sar(TMPR)
          end

          context.set_reg_content(TMPR, vnode)
          context.ret_reg = TMPR
          context
        end
      end

      module FloatTypeBoxedCodeGen
        include AbsArch
        include CommonCodeGen

        def gen_boxing(context)
          context
        end

        def gen_unboxing(context)
          asm = context.assembler
          fobj = TypedData.new(InternalRubyType::RFloat, context.ret_reg)
          asm.with_retry do
            asm.movsd(XMM0, fobj[:float_value])
          end

          context.ret_reg = XMM0
          context
        end
      end

      module FloatTypeUnboxedCodeGen
        include AbsArch
        include CommonCodeGen

        def gen_boxing(context)
          asm = context.assembler
          val = context.ret_reg
          vnode = context.ret_node
          context.start_using_reg(TMPR2)
          context.start_arg_reg(FUNC_FLOAT_ARG)
          context.start_arg_reg
          addr = lambda {
            a = address_of("rb_float_new")
            $symbol_table[a] = "rb_float_new"
            a
          }
          rbfloatnew = OpVarMemAddress.new(addr)
=begin
          # This is sample of backtrace
          sh = OpMemAddress.new(address_of("ytl_step_handler"))
          context = gen_save_thepr(context)
          context = gen_call(context, sh, 0, vnode)
=end
          asm.with_retry do
            asm.mov(FUNC_FLOAT_ARG[0], val)
          end
          context.set_reg_content(FUNC_FLOAT_ARG[0].dst_opecode, vnode)
          context = gen_save_thepr(context)
          context = gen_call(context, rbfloatnew, 1, vnode)
          context.end_arg_reg
          context.end_arg_reg(FUNC_FLOAT_ARG)
#          context.end_using_reg(TMPR3)
          context.end_using_reg(TMPR2)
          context.ret_reg = RETR
          context
        end

        def include_nil?
          false
        end

        def gen_unboxing(context)
          context
        end
      end

      module ArrayTypeCommonCodeGen
        def init
          @element_type = nil
        end

        attr_accessor :element_type

        def have_element?
          true
        end

        def ==(other)
          if other then
            oc = other.ruby_type
            sc = self.ruby_type
            sc == oc and
              ((other.element_type == nil and
               @element_type == nil) or
               (other.element_type and @element_type and
                @element_type[nil] == other.element_type[nil])) and
              boxed == other.boxed
          else
            false
          end
        end

=begin
        def eql?(other)
          if other then
            oc = other.ruby_type
            sc = self.ruby_type

            sc == oc and
              boxed == other.boxed
          else
            false
          end
        end
=end

        def inspect
          etype = @element_type.inspect
          "{ #{boxed ? "BOXED" : "UNBOXED"} #{@ruby_type} (#{etype})}"
        end
      end

      module ArrayTypeBoxedCodeGen
        include AbsArch
        include CommonCodeGen
        include ArrayTypeCommonCodeGen

        def instance
          ni = self.dup
          ni.instance_eval { extend ArrayTypeBoxedCodeGen }
          ni.init
          ni
        end

        def gen_copy(context)
          asm = context.assembler
          val = context.ret_reg
          vnode = context.ret_node
          context.start_arg_reg
          addr = lambda {
            a = address_of("rb_ary_dup")
            $symbol_table[a] = "rb_ary_dup"
            a
          }
          rbarydup = OpVarMemAddress.new(addr)
          asm.with_retry do
            asm.mov(FUNC_ARG[0], val)
          end
          context.set_reg_content(FUNC_ARG[0].dst_opecode, vnode)
          context = gen_save_thepr(context)
          context = gen_call(context, rbarydup, 1, vnode)
          context.end_arg_reg
          context.ret_reg = RETR

          context
        end

        def copy_type
          dao = self.class.from_ruby_class(@ruby_type)
          dao = dao.to_box
          dao.element_type = @element_type
          dao
        end
      end

      module ArrayTypeUnboxedCodeGen
        include ArrayTypeCommonCodeGen
        include SendNodeCodeGen

        def instance
          ni = self.dup
          ni.instance_eval { extend ArrayTypeUnboxedCodeGen }
          ni.init
          ni
        end

        def gen_boxing(context)
#          raise "foo"
          return context
          cursig = context.to_signature
          asm = context.assembler
          val = context.ret_reg
          vnode = context.ret_node
          etypel = []
          vnode.element_node_list[1..-1].each do |a|
            if a[3] then
              curidx = a[3][0]
              if etypel[curidx] == nil then
                etypel[curidx] = a[2].decide_type_once(a[1])
              end
            end
          end
          siz = etypel.size

          context.start_using_reg(TMPR3)
          context.start_using_reg(TMPR2)
          asm.with_retry do
            asm.mov(TMPR3, val)
          end

          argcomp = lambda {|context, arg, idx|
            eleacc = OpIndirect.new(TMPR3, idx * AsmType::MACHINE_WORD.size)
            asm.with_retry do
              asm.mov(TMPR2, eleacc)
            end
            context.ret_reg = TMPR2
            arg
          }

          context = gen_make_argv(context, etypel, argcomp) do |context, rarg|
            context.start_arg_reg
            context.cpustack_pushn(2 * AsmType::MACHINE_WORD.size)

            addr = lambda {
              a = address_of("rb_ary_new4")
              $symbol_table[a] = "rb_ary_new4"
              a
            }
            rbarynew = OpVarMemAddress.new(addr)
            asm.with_retry do
              asm.mov(FUNC_ARG[0], siz)
              asm.mov(FUNC_ARG[1], TMPR2)
            end

            context = gen_save_thepr(context)
            context = gen_call(context, rbarynew, 2, vnode)
            context.cpustack_popn(2 * AsmType::MACHINE_WORD.size)
            context.end_arg_reg
            context.ret_reg = RETR
            context.set_reg_content(context.ret_reg, vnode)
            context
          end

          context.end_using_reg(TMPR2)
          context.end_using_reg(TMPR3)
          context
        end


        def copy_type
          dao = self.class.from_ruby_class(@ruby_type)
          dao = dao.to_unbox
          dao.element_type = @element_type
          dao
        end
      end

      module StringTypeBoxedCodeGen
        include AbsArch
        include CommonCodeGen

        def gen_copy(context)
          asm = context.assembler
          val = context.ret_reg
          vnode = context.ret_node
          context.start_arg_reg
          addr = lambda {
            a = address_of("rb_str_dup")
            $symbol_table[a] = "rb_str_dup"
            a
          }
          rbstrdup = OpVarMemAddress.new(addr)
          asm.with_retry do
            asm.mov(FUNC_ARG[0], val)
          end
          context.set_reg_content(FUNC_ARG[0].dst_opecode, vnode)
          context = gen_save_thepr(context)
          context = gen_call(context, rbstrdup, 1, vnode)
          context.end_arg_reg
          context.ret_reg = RETR
          
          context
        end
      end

      module RangeTypeCommonCodeGen
        def init
          @args = nil
          @element_type = nil
        end

        attr_accessor :args
        attr_accessor :element_type

        def have_element?
          true
        end

        def inspect
          "{ #{boxed ? "BOXED" : "UNBOXED"} #{@ruby_type} (#{@element_type.inspect})}"
        end

        def ==(other)
          self.class == other.class and
#            @args == other.args and
            boxed == other.boxed
        end
      end

      module RangeTypeBoxedCodeGen
        include RangeTypeCommonCodeGen

        def instance
          ni = self.dup
          ni.instance_eval { extend RangeTypeBoxedCodeGen }
          ni.init
          ni
        end

        def copy_type
          dro = self.class.from_ruby_class(@ruby_type)
          dro = dro.to_box
          dro.element_type = @element_type
          dro.args = @args
          dro
        end
      end

      module RangeTypeUnboxedCodeGen
        include AbsArch
        include CommonCodeGen
        include RangeTypeCommonCodeGen

        def instance
          ni = self.dup
          ni.instance_eval { extend RangeTypeUnboxedCodeGen }
          ni.init
          ni
        end

        def gen_boxing(context)
          rtype = @args[0].decide_type_once(context.to_signature)

          vnode = context.ret_node
          base = context.ret_reg
          addr = lambda {
            a = address_of("rb_range_new")
            $symbol_table[a] = "rb_range_new"
            a
          }
          rbrangenew = OpVarMemAddress.new(addr)
          begoff = OpIndirect.new(TMPR2, 0)
          endoff = OpIndirect.new(TMPR2, AsmType::MACHINE_WORD.size)
          excoff = OpIndirect.new(TMPR2, AsmType::MACHINE_WORD.size * 2)
 
          context.start_using_reg(TMPR2)
          context.start_arg_reg
          asm = context.assembler
          asm.with_retry do
            asm.mov(TMPR2, base)
          end

          context.ret_reg = begoff
          context = rtype.gen_boxing(context)
          asm.with_retry do
            asm.mov(FUNC_ARG[0], context.ret_reg)
          end

          context.ret_reg = endoff
          context = rtype.gen_boxing(context)
          asm.with_retry do
            asm.mov(FUNC_ARG[1], context.ret_reg)
          end

          asm.with_retry do
            asm.mov(FUNC_ARG[2], excoff)
          end
          context = gen_save_thepr(context)
          context = gen_call(context, rbrangenew, 3, vnode)

          context.end_arg_reg
          context.end_using_reg(TMPR2)
          context.ret_reg = RETR
          context
        end

        def copy_type
          dro = self.class.from_ruby_class(@ruby_type)
          dro = dro.to_unbox
          dro.element_type = @element_type
          dro.args = @args
          dro
        end
      end
    end
  end
end
