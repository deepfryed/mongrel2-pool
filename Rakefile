require 'rake'

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name        = 'mongrel2-pool'
    gem.summary     = %q{rack-mongrel2 based worker pool.}
    gem.description = %q{rack-mongrel2 based worker pool.}
    gem.email       = %w{deepfryed@gmail.com}
    gem.homepage    = 'http://github.com/deepfryed/mongrel2-pool'
    gem.authors     = ["Bharanee Rathna"]
    gem.files.reject!{|f| f =~ %r{\.gitignore|examples/.*}}

    gem.add_dependency 'rack-mongrel2'
    gem.add_development_dependency 'minitest', '>= 1.7.0'
  end
  Jeweler::GemcutterTasks.new
rescue LoadError
  puts "Jeweler (or a dependency) not available. Install it with: gem install jeweler"
end

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

task :test    => :check_dependencies
task :default => :test

require 'yard'
YARD::Rake::YardocTask.new do |yard|
  yard.files   = ['lib/**/*.rb']
end

