# typed: true
# frozen_string_literal: true

# RSpec includes these modules when configuring the expectation and mock frameworks.
class RSpec::Core::ExampleGroup
  include ::RSpec::Mocks::ExampleMethods
  include ::RSpec::Matchers
end

module RSpec::Matchers
  # Zero-argument predicate matchers supplied dynamically by method_missing.
  sig { returns(::RSpec::Matchers::BuiltIn::BePredicate) }
  def be_empty; end

  sig { returns(::RSpec::Matchers::BuiltIn::BePredicate) }
  def be_flat; end

  sig { returns(::RSpec::Matchers::BuiltIn::BePredicate) }
  def be_workspaces; end
end
