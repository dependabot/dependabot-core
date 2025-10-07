# typed: false
# frozen_string_literal: true

require_relative "support/helpers"
require_relative "support/ecosystem_scaffolder"

# Rake task for scaffolding new ecosystems
# sorbet: ignore
namespace :ecosystem do
  desc "Scaffold a new ecosystem (e.g., rake ecosystem:scaffold[bazel])"
  task :scaffold, [:name] do |_t, args|
    if args[:name].nil? || args[:name].strip.empty?
      puts "Error: Ecosystem name is required."
      puts "Usage: rake ecosystem:scaffold[ecosystem_name]"
      exit 1
    end

    ecosystem_name = args[:name].strip.downcase

    # Validate ecosystem name format
    unless ecosystem_name.match?(/^[a-z][a-z0-9_]*$/)
      puts "Error: Ecosystem name must start with a letter and contain only " \
           "lowercase letters, numbers, and underscores."
      exit 1
    end

    # Check if ecosystem already exists
    if Dir.exist?(ecosystem_name)
      puts "Error: Directory '#{ecosystem_name}' already exists."
      exit 1
    end

    puts "Scaffolding new ecosystem: #{ecosystem_name}"
    puts ""

    scaffolder = EcosystemScaffolder.new(ecosystem_name)
    scaffolder.scaffold

    puts ""
    puts "✅ Ecosystem '#{ecosystem_name}' has been scaffolded successfully!"
    puts ""
    puts "Next steps:"
    puts "1. Implement the core classes in #{ecosystem_name}/lib/dependabot/#{ecosystem_name}/"
    puts "2. Add tests in #{ecosystem_name}/spec/dependabot/#{ecosystem_name}/"
    puts "3. Update supporting infrastructure (CI workflows, omnibus gem, etc.)"
    puts "4. See NEW_ECOSYSTEMS.md for complete implementation guide"
  end
end
