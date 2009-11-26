SPEC = Gem::Specification.new do |s|
  s.name          = "odb"
  s.summary       = "An Object Oriented Database for Ruby" 
  s.version       = "0.1.0"
  s.date          = "2009-11-25"
  s.author        = "Loren Segal"
  s.email         = "lsegal@soen.ca"
  s.homepage      = "http://gnuu.org"
  s.platform      = Gem::Platform::RUBY
  s.files         = Dir.glob("{lib,spec}/**/*") + ['LICENSE', 'README.rdoc', 'Rakefile']
  s.require_paths = ['lib']
  s.has_rdoc      = 'yard'
  s.rubyforge_project = 'odb'
  #s.add_dependency 'tadpole' 
end