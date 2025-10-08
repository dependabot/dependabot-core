# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require_relative "infrastructure_updaters/base_updater"
require_relative "infrastructure_updaters/github_workflow_updater"
require_relative "infrastructure_updaters/script_updater"
require_relative "infrastructure_updaters/gem_infrastructure_updater"

# Orchestrator class that coordinates infrastructure updates for a new ecosystem
# Delegates to specialized updater classes for different infrastructure concerns
class EcosystemInfrastructureUpdater
  extend T::Sig

  sig { params(name: String, overwrite_mode: String).void }
  def initialize(name, overwrite_mode = "ask")
    @ecosystem_name = T.let(name, String)
    @overwrite_mode = T.let(overwrite_mode, String)
    @github_updater = T.let(
      GitHubWorkflowUpdater.new(name),
      GitHubWorkflowUpdater
    )
    @script_updater = T.let(
      ScriptUpdater.new(name),
      ScriptUpdater
    )
    @gem_updater = T.let(
      GemInfrastructureUpdater.new(name),
      GemInfrastructureUpdater
    )
  end

  sig { void }
  def update_infrastructure
    puts "Updating supporting infrastructure for ecosystem: #{@ecosystem_name}"
    puts "Overwrite mode: #{@overwrite_mode}"
    puts ""

    # Verify ecosystem exists
    unless ecosystem_exists?
      puts "Error: Ecosystem '#{@ecosystem_name}' not found. Please scaffold it first."
      exit 1
    end

    # Delegate to specialized updaters
    @github_updater.update_all
    @script_updater.update_all
    @gem_updater.update_all

    print_summary
  end

  private

  sig { returns(T::Boolean) }
  def ecosystem_exists?
    ecosystem_dir = "#{@ecosystem_name}/lib/dependabot/#{@ecosystem_name}.rb"
    File.exist?(ecosystem_dir)
  end

  sig { void }
  def print_summary
    all_changes = @github_updater.changes_made +
                  @script_updater.changes_made +
                  @gem_updater.changes_made

    puts "\n" + ("=" * 80)
    puts "Infrastructure Update Summary"
    puts "=" * 80

    if all_changes.empty?
      puts "No changes were made. All infrastructure is up to date."
    else
      puts "Successfully updated #{all_changes.size} file(s):"
      all_changes.each do |change|
        puts "  ✓ #{change}"
      end
    end

    puts "=" * 80
    puts ""
    puts "Next steps:"
    puts "1. Review the changes made to ensure correctness"
    puts "2. Update omnibus gem dependencies: cd omnibus && bundle install"
    puts "3. Update updater dependencies: cd updater && bundle install"
    puts "4. Test the ecosystem with: bin/docker-dev-shell #{@ecosystem_name}"
    puts "5. See NEW_ECOSYSTEMS.md for complete implementation guide"
  end
end
