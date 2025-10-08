# typed: strong
# frozen_string_literal: true

# Helper methods for ecosystem rake tasks
module EcosystemHelpers
  extend T::Sig

  sig { params(ecosystem_name: String).void }
  def self.print_next_steps_scaffold(ecosystem_name)
    puts ""
    puts "Next steps:"
    [
      "Implement the core classes in #{ecosystem_name}/lib/dependabot/#{ecosystem_name}/",
      "Add tests in #{ecosystem_name}/spec/dependabot/#{ecosystem_name}/",
      "Update supporting infrastructure with: rake ecosystem:update_infrastructure[#{ecosystem_name}]",
      "See NEW_ECOSYSTEMS.md for complete implementation guide"
    ].each { |step| puts "  • #{step}" }
  end

  sig { params(ecosystem_name: String).void }
  def self.print_next_steps_infrastructure(ecosystem_name)
    puts ""
    puts "Next steps:"
    [
      "Review the changes made to ensure correctness",
      "Update omnibus gem dependencies: cd omnibus && bundle install",
      "Update updater dependencies: cd updater && bundle install",
      "Test the ecosystem with: bin/docker-dev-shell #{ecosystem_name}",
      "See NEW_ECOSYSTEMS.md for complete implementation guide"
    ].each { |step| puts "  • #{step}" }
  end

  sig { params(ecosystem_name: String).void }
  def self.print_next_steps_create(ecosystem_name)
    puts ""
    puts "Next steps:"
    [
      "Implement the core classes in #{ecosystem_name}/lib/dependabot/#{ecosystem_name}/",
      "Add tests in #{ecosystem_name}/spec/dependabot/#{ecosystem_name}/",
      "Update omnibus dependencies: cd omnibus && bundle install",
      "Update updater dependencies: cd updater && bundle install",
      "Test the ecosystem with: bin/docker-dev-shell #{ecosystem_name}",
      "See NEW_ECOSYSTEMS.md for complete implementation guide"
    ].each { |step| puts "  • #{step}" }
  end
end
