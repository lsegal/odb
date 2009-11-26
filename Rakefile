require File.dirname(__FILE__) + '/lib/odb'
require 'rubygems'
require 'rake/gempackagetask'

WINDOWS = (PLATFORM =~ /win32|cygwin/ ? true : false) rescue false
SUDO = WINDOWS ? '' : 'sudo'

task :default => :specs

load 'odb.gemspec'
Rake::GemPackageTask.new(SPEC) do |pkg|
  pkg.gem_spec = SPEC
  pkg.need_zip = true
  pkg.need_tar = true
end

desc "Install the gem locally"
task :install => :gem do 
  sh "#{SUDO} gem install pkg/#{SPEC.name}-#{SPEC.version}.gem --local --no-rdoc --no-ri"
  sh "rm -rf pkg/odb-#{SPEC.version}" unless ENV['KEEP_FILES']
end

begin
  require 'spec'
  require 'spec/rake/spectask'

  desc "Run all specs"
  Spec::Rake::SpecTask.new("specs") do |t|
    $DEBUG = true if ENV['DEBUG']
    t.spec_opts = ["--format", "specdoc", "--colour"]
    t.spec_opts += ["--require", File.join(File.dirname(__FILE__), 'spec', 'spec_helper')]
    t.spec_files = Dir["spec/**/*_spec.rb"].sort
  
    if ENV['RCOV']
      hide = '_spec\.rb$,spec_helper\.rb$,ruby_lex\.rb$,autoload\.rb$'
      hide += ',legacy\/.+_handler,html_syntax_highlight_helper18\.rb$' if RUBY19
      hide += ',ruby_parser\.rb$,ast_node\.rb$,handlers\/ruby\/[^\/]+\.rb$,html_syntax_highlight_helper\.rb$' if RUBY18
      t.rcov = true 
      t.rcov_opts = ['-x', hide]
    end
  end
  task :spec => :specs
rescue LoadError
  warn "warn: RSpec tests not available. `gem install rspec` to enable them."
end

begin
  require 'yard'
  YARD::Rake::YardocTask.new
rescue LoadError
  warn "warn: YARD is not available. `gem install yard` to enable documentation generation"
end