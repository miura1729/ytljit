spec = Gem::Specification.new do |s|
     s.platform     = Gem::Platform::RUBY
     s.name         = "ytljit"
     s.version      = "0.0.5"
     s.summary      = "native code generator for ruby compiler"
     s.authors      = ["Hideki Miura"]
     s.files        = [*Dir.glob("{lib}/*.rb"),
                       *Dir.glob("{lib}/ytljit/*.rb"),
                       *Dir.glob("{lib}/runtime/*.rb"),
                       *Dir.glob("{ext}/*.c"), 
                       *Dir.glob("{ext}/*.h"), 
                       *Dir.glob("{ext}/*.rb"), 
                       *Dir.glob("{test}/*.rb"), 
		       "README", "Rakefile"]
     s.require_path = "lib"
     s.extensions << 'ext/extconf.rb'
     s.test_files   =	Dir.glob("{test}/*.rb")
     s.add_dependency('iseq')
end
