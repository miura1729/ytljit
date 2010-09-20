#

require "rbconfig"

ruby_bin = File.join(RbConfig::CONFIG["bindir"], RbConfig::CONFIG["ruby_install_name"])

desc "compile ytljit_ext extension library"
task :ext do
  Dir.chdir("ext") do
    sh "#{ruby_bin} extconf.rb"
    sh "make"
  end
end

desc "run tests"
task :test do
  Dir.glob(File.join("test", "*.rb")) do |f|
    sh "#{ruby_bin} -I./ext -I./lib " + f
  end
end

task :default => [:ext, :test]
