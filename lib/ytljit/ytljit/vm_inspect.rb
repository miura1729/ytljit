require 'tempfile'

module YTLJit
  module VM
    module Node
      module Inspect
        def inspect_by_graph
          Inspector.new(self)
        end
      end

      class Inspector
        def initialize(obj)
          File.open('vm_struct.dot', "w") {|fp|
            @fp = fp
            @appear_objects = {}
            @appear_objects[obj.__id__] = true
            @fp.print "digraph G {\n"
            inspect_aux(obj)
            @fp.print "#{obj.__id__} [label=\"#{obj.class.name}\"]\n"
            @fp.print "}\n"
          }
        end
        
        def inspect_aux(obj)
          case obj
          when Array
            i = 0
            obj.each do |vobj|
              emit(obj, vobj)
              @fp.print "#{obj.__id__} -> #{vobj.__id__} [label=\"#{i}\"]\n"
              i += 1
            end
            
          when Hash
            obj.each do |key, vobj|
              emit(obj, vobj)
              if key or vobj then
                @fp.print "#{obj.__id__} -> #{vobj.__id__} [label=\"#{key}\"]\n"
              end
            end
            
          else
            obj.instance_variables.each do |vstr|
              vobj = obj.instance_variable_get(vstr)
              if vobj then
                @fp.print "#{obj.__id__} -> #{vobj.__id__} [label=\"#{vstr}\"]\n"
              end
              emit(obj, vobj)
            end
          end
        end
        private :inspect_aux
        
        def emit(pobj, vobj)
          if vobj.is_a?(Symbol) or vobj.is_a?(Fixnum) or vobj.is_a?(String) then
            @fp.print "#{vobj.__id__} [label=\"#{vobj.inspect}\"]\n"
          else
            @fp.print "#{vobj.__id__} [label=\"#{vobj.class.name}\"]\n"
          end
          if @appear_objects[vobj.__id__] != true then
            @appear_objects[vobj.__id__] = true
            inspect_aux(vobj)
          end
        end
        private :emit
      end 
    end
  end
end
