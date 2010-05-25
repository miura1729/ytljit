module YTLJit

=begin
  Stack layout (on stack frame)


Hi     |  |Argn                   |   |
       |  |   :                   |   |
       |  |Arg3(exception status) |   |
       |  |Arg2(block pointer)    |   |
       |  |Arg1(parent frame)     |  -+
       |  |Arg0(self)             |
       |  |Return Address         |
       +- |old bp                 | <-+
          |old bp on stack        |  -+
    EBP-> |Local Vars1            |   
          |                       |   
          |                       |   
          |Local Varsn            |   
          |Pointer to Env         |   
   SP ->  |                       |
          |                       |
LO        


  Stack layout (on heap frame)


Hi     |  |Arg0(self)             |   |
       |  |Arg1(parent frame)     |  -+
       |  |Arg2(block pointer)    |
       |  |Arg3(exception status) |
       |  |   :                   |
       |  |Arg n                  |
       |  |Return Address         |
       +- |old bp                 |  <---+
          |Pointer to Env         |  -+  |
   SP ->  |                       |   |  |
LO        |                       |   |  |
                                      |  |
                                      |  |
       +- |                       |   |  |
       |  |free func              |   |  |
       |  |mark func              |   |  |
       |  |T_DATA                 | <-+  |                                      
       |                                 |
       |                                 |
       |  |Arg n                  |      |
       |  |   :                   |      |
       |  |Arg3(exception status) |      |
       |  |Arg2(block pointer)    |      |
       |  |Arg1(parent frame)     |      |
       |  |Arg0(self)             |      |   
       |  |Not used(reserved)     |      |
       |  |Not used(reserved)     |      |
       |  |old bp on stack        | -----+
    EBP-> |Local Vars1            |   
       |  |                       |   
       |  |                       |   
       +->|Local Varsn            |   

  enter procedure
    push EBP
    SP -> EBP
    allocate frame (stack or heap)    
    Copy arguments if allocate frame on heap
    store EBP on the top of frame
    Address of top of frame -> EBP
 
  leave procedure
    Dereference of EBP -> ESP
    pop EBP
    ret

=end

  module VM
    class Context
      def initialize
        @code_space = cs
        @assembler = asm
        
        # RETR(EAX, RAX) or RETFR(STO, XM0) or Immdiage object
        @ret_reg = RETR
      end

      attr_accessor :code_space
      attr_accessor :assembler
      attr_accessor :ret_reg

      def add_code_space(cs)
        @code_space = cs
        @assembler = Assembler.new(cs)
      end
    end

    module Node
      module MethodTopCodeGen
        include AbsArch

        def gen_method_prologe(context)
          asm = context.assembler
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
      end

      module MethodEndCodeGen
        include AbsArch

        def gen_method_eplogue(context)
          asm = context.assembler

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

      module IfNodeCodeGen
        include AbsArch

        def unify_retreg_tpart(tretr, eretr, asm)
        end

        def unify_retreg_epart(tretr, eretr, asm)
        end

        def unify_retreg_cont(tretr, eretr, asm)
        end
      end
      
      module LocalVarNodeCodeGen
        include AbsArch

        def offset_arg(n)
          off = 16 + n * Type::MACHINE_WORD.size
          OpIndirect.new(TMPR, off)
        end

        def gen_pursue_parent_function(context, depth)
          asm = context.assembler
          asm.mov(BPR, TMPR)
          depth.times do 
            asm.mov(TMPR, offset_arg(0))
          end
          
          context.ret_reg = TMPR
          context
        end
      end

    end
  end
end
