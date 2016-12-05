require "rubocop/rake_task"
RuboCop::RakeTask.new

require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:spec)

# This is run by default by Travis
task default: [:rubocop, :spec]
