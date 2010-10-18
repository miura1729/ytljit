spec = Gem::Specification.new do |s|
     s.platform     = Gem::Platform::RUBY
     s.name         = "ytljit"
     s.version      = "0.0.0"
     s.summary      = "native code generator for ruby compiler"
     s.authors      = ["Hideki Miura"]
     s.files        = [*Dir.glob("{lib}/**/*"),
                       *Dir.glob("{ext}/**/*"), 
                       *Dir.glob("{test}/**/*"), 
		       "README", "Rakefile"]
     s.require_path = "lib"
     s.extensions << 'ext/extconf.rb'
     s.test_files   =	Dir.glob("{test}/**/*")
end
		       
 
		      
		       

       
