# typed: strict
# frozen_string_literal: true

require_relative "support/helpers"
require_relative "support/ecosystem_scaffolder"
require_relative "support/ecosystem_infrastructure_updater"

# Rake task for scaffolding new ecosystems
# sorbet: ignore
namespace :ecosystem do
  desc "Scaffold a new ecosystem (e.g., rake ecosystem:scaffold[bazel,ask])"
  task :scaffold, [:name, :overwrite] do |_t, args|
    if args[:name].nil? || args[:name].strip.empty?
      puts "Error: Ecosystem name is required."
      puts "Usage: rake ecosystem:scaffold[ecosystem_name] or rake ecosystem:scaffold[ecosystem_name,overwrite_mode]"
      puts "Overwrite modes: ask (default), skip, force"
      exit 1
    end

    ecosystem_name = args[:name].strip.downcase
    overwrite_mode = (args[:overwrite] || "ask").strip.downcase

    # Validate ecosystem name format
    unless ecosystem_name.match?(/^[a-z][a-z0-9_]*$/)
      puts "Error: Ecosystem name must start with a letter and contain only " \
           "lowercase letters, numbers, and underscores."
      exit 1
    end

    # Validate overwrite mode
    unless %w(ask skip force).include?(overwrite_mode)
      puts "Error: Invalid overwrite mode '#{overwrite_mode}'."
      puts "Valid modes: ask, skip, force"
      exit 1
    end

    puts "Scaffolding new ecosystem: #{ecosystem_name}"
    puts "Overwrite mode: #{overwrite_mode}"
    puts ""

    scaffolder = EcosystemScaffolder.new(ecosystem_name, overwrite_mode)
    scaffolder.scaffold

    puts ""
    puts "✅ Ecosystem '#{ecosystem_name}' has been scaffolded successfully!"
    puts ""
    puts "Next steps:"
    puts "1. Implement the core classes in #{ecosystem_name}/lib/dependabot/#{ecosystem_name}/"
    puts "2. Add tests in #{ecosystem_name}/spec/dependabot/#{ecosystem_name}/"
    puts "3. Update supporting infrastructure with: rake ecosystem:update_infrastructure[#{ecosystem_name}]"
    puts "4. See NEW_ECOSYSTEMS.md for complete implementation guide"
  end

  desc "Update supporting infrastructure for an ecosystem (e.g., rake ecosystem:update_infrastructure[bazel])"
  task :update_infrastructure, [:name] do |_t, args|
    if args[:name].nil? || args[:name].strip.empty?
      puts "Error: Ecosystem name is required."
      puts "Usage: rake ecosystem:update_infrastructure[ecosystem_name]"
      exit 1
    end

    ecosystem_name = args[:name].strip.downcase

    # Validate ecosystem name format
    unless ecosystem_name.match?(/^[a-z][a-z0-9_]*$/)
      puts "Error: Ecosystem name must start with a letter and contain only " \
           "lowercase letters, numbers, and underscores."
      exit 1
    end

    updater = EcosystemInfrastructureUpdater.new(ecosystem_name, "force")
    updater.update_infrastructure
  end
end
