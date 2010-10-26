module YTLJit
  module Runtime
    class GCBase
      def gc(heap)
        raise "#{heap} is overflow"
      end
      
      def malloc(type)
      end
    end
    
    class GCCopy<GCBase
      def initialize
        @arena = []
        @arena[0] = Arena.new
        @arena[1] = Arena.new
        @from_arena = 0
      end
      
      def gc
      end
      
      def malloc(type)
        siz = type.size
        siz += YTLObject.size
        fromare = @arena[@from_arena]
        if fromare.size < fromare.using + siz then
          gc
        end
        
        res = TypedDataArena.new(YTLObject, fromare, fromare.using)
        fromare.using += siz

        # Initialize object header
        yield res
        
        res.cast(type)
      end
    end
  end
end
