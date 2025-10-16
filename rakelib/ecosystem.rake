# typed: strict
# frozen_string_literal: true

require_relative "support/helpers"
require_relative "support/ecosystem_scaffolder"
require_relative "support/ecosystem_infrastructure_updater"
require_relative "support/ecosystem_helpers"

# Rake task for scaffolding new ecosystems
# rubocop:disable Metrics/BlockLength
# sorbet: ignore
namespace :ecosystem do
  desc "Scaffold a new ecosystem (e.g., rake ecosystem:scaffold[bazel,ask])"
  task :scaffold, [:name, :overwrite, :quiet] do |_t, args|
    if args[:name].nil? || args[:name].strip.empty?
      puts "Error: Ecosystem name is required."
      puts "Usage: rake ecosystem:scaffold[ecosystem_name] or rake ecosystem:scaffold[ecosystem_name,overwrite_mode]"
      puts "Overwrite modes: ask (default), skip, force"
      exit 1
    end

    ecosystem_name = args[:name].strip.downcase
    overwrite_mode = (args[:overwrite] || "ask").strip.downcase
    quiet = args[:quiet] == "true"

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

    unless quiet
      puts "Scaffolding new ecosystem: #{ecosystem_name}"
      puts "Overwrite mode: #{overwrite_mode}"
      puts ""
    end

    scaffolder = EcosystemScaffolder.new(ecosystem_name, overwrite_mode)
    scaffolder.scaffold

    unless quiet
      puts ""
      puts "✅ Ecosystem '#{ecosystem_name}' has been scaffolded successfully!"
      EcosystemHelpers.print_next_steps_scaffold(ecosystem_name)
    end
  end

  desc "Update supporting infrastructure for an ecosystem (e.g., rake ecosystem:update_infrastructure[bazel])"
  task :update_infrastructure, [:name, :quiet] do |_t, args|
    if args[:name].nil? || args[:name].strip.empty?
      puts "Error: Ecosystem name is required."
      puts "Usage: rake ecosystem:update_infrastructure[ecosystem_name]"
      exit 1
    end

    ecosystem_name = args[:name].strip.downcase
    quiet = args[:quiet] == "true"

    # Validate ecosystem name format
    unless ecosystem_name.match?(/^[a-z][a-z0-9_]*$/)
      puts "Error: Ecosystem name must start with a letter and contain only " \
           "lowercase letters, numbers, and underscores."
      exit 1
    end

    updater = EcosystemInfrastructureUpdater.new(ecosystem_name, "force", quiet: quiet)
    updater.update_infrastructure

    next if quiet

    EcosystemHelpers.print_next_steps_infrastructure(ecosystem_name)
  end

  desc "Create a new ecosystem with full infrastructure (e.g., rake ecosystem:create[bazel])"
  task :create, [:name, :overwrite] do |_t, args|
    ecosystem_name = args[:name]&.strip&.downcase
    overwrite_mode = (args[:overwrite] || "ask").strip.downcase

    puts "=" * 80
    puts "Creating new ecosystem: #{ecosystem_name}"
    puts "Overwrite mode: #{overwrite_mode}"
    puts "=" * 80
    puts ""

    # Step 1: Scaffold the ecosystem (includes validation)
    puts "Step 1: Scaffolding ecosystem structure..."
    puts "-" * 80
    Rake::Task["ecosystem:scaffold"].invoke(ecosystem_name, overwrite_mode, "true")

    puts ""
    puts "Step 2: Updating supporting infrastructure..."
    puts "-" * 80
    Rake::Task["ecosystem:update_infrastructure"].invoke(ecosystem_name, "true")

    puts ""
    puts "=" * 80
    puts "✅ Ecosystem '#{ecosystem_name}' has been created successfully!"
    puts "=" * 80
    EcosystemHelpers.print_next_steps_create(ecosystem_name)
  end
end
# rubocop:enable Metrics/BlockLength
