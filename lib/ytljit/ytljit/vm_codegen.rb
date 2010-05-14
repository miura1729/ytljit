module YTLJit

  module VM
    class Context
      def initialize(cs)
        @code_space = cs
        
        # RETR(EAX, RAX) or RETFR(STO, XM0)
        @ret_reg = RETR
      end

      attr_accessor :code_space
    end

    module Node
      module MethodTopCodeGen
        include AbsArch

        def gen_method_prologe(context)
          curcs = context.code_space
          asm = Assembler.new(curcs)
          lsize = @local_vars.inject(0) {|res, ele| res += ele.size}
          wsize = @work_area.inject(0) {|res, ele| res += ele.size}
          @frame_size = lsize + wsize

          if @frame_size != 0 then

            # Make linkage of frame pointer
            asm.push BPR
            asm.mov BPR, SPR
            asm.push BPR
            asm.mov BPR, SPR

            # Make Local Variable area
            asm.add BSP, (lwsize)
            
          else
            # No local var. and work area
          end

          context
        end

      module MethodEndCodeGen
        include AbsArch

        def gen_method_eplogue(context)
          curcs = context.code_space
          asm = Assembler.new(curcs)

          if @parent_method.frame_size != 0 then

            # Make linkage of frame pointer
            asm.mov BSP, BPR
            asm.pop BPR
            asm.mov BSP, BPR
            asm.pop BPR

          else
            # No local var. and work area
          end

          context
        end
      end
    end
  end
end
