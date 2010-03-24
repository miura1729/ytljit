module YTLJit
  module Type
    class StructMember<TypeCommon
      def initialize(type, offset)
        @type = type
        @offset = offset
      end

      attr :type
      attr :offset

      def size
        @type.size
      end

      def [](name)
        @type[name, @offset]
      end
    end

    class Struct<TypeCommon
      def initialize(*spec)
        @member = []
        @size = nil
        stat = 0
        curvar = []
        spec.each do |token|
          case stat
          when 0
            curvar.push token
            stat = 1
            
          when 1
            curvar.push token
            stat = 2
            
          when 2
            if token.is_a?(Integer) then
              curvar.push token
              @member.push curvar
              curvar = []
              stat = 0
            else
              @member.push curvar
              if token then
                curvar = [token]
                stat = 1
              else
                curvar = []
                stat = 0
              end
            end
          end
          # assert(stat == 0)
        end
        @member.push curvar
      end

      def offset_of(name, base = 0)
        offset = 0
        @member.each do |e|
          if e[1] == name then
            return offset + base
          end
          offset += e[2] ? e[2] : e[0].size
        end
        raise "No such member #{name} in #{self}"
      end

      def type_of(name)
        offset = 0
        @member.each do |e|
          if e[1] == name then
            return e[0]
          end
        end
        raise "No such member #{name} in #{self}"
      end

      def size
        if @size then
          @size
        else
          @size = 0
          @member.each do |e|
            @size += e[2] ? e[2] : e[0].size
          end
          @size
        end
      end

      def [](name, base = 0)
        offset = 0
        @member.each do |e|
          if e[1] == name then
            return StructMember.new(e[0], offset + base)
          end
          offset += e[2] ? e[2] : e[0].size
        end
        raise "No such member #{name} in #{self}"
      end
    end

    class Union<Struct
      def offset_of(name, base = 0)
        base
      end

      def size
        if @size then
          @size
        else
          @size = 0
          @member.each do |e|
            @size = [@size, e[2] ? e[2] : e[0].size].max
          end
          @size
        end
      end

      def [](name, base = 0)
        StructMember.new(type_of(name), base)
      end
    end
  end
end
