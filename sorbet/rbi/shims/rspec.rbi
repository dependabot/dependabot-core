# typed: strict
# frozen_string_literal: true

module RSpec
  module Core
    # RSpec includes these modules when configuring the expectation and mock frameworks.
    class ExampleGroup
      include ::RSpec::Mocks::ExampleMethods
      include ::RSpec::Matchers
    end
  end

  module Matchers
    # Predicate matchers supplied dynamically by method_missing.
    sig { returns(::RSpec::Matchers::BuiltIn::BePredicate) }
    def be_empty; end

    sig { returns(::RSpec::Matchers::BuiltIn::BePredicate) }
    def be_flat; end

    sig { returns(::RSpec::Matchers::BuiltIn::BePredicate) }
    def be_workspaces; end

    sig { returns(::RSpec::Matchers::BuiltIn::BePredicate) }
    def be_positive; end

    sig { params(version: T.anything).returns(::RSpec::Matchers::BuiltIn::BePredicate) }
    def be_satisfied_by(version); end

    sig { params(name: T.any(String, Symbol)).returns(::RSpec::Matchers::BuiltIn::BePredicate) }
    def be_enabled(name); end

    sig { params(key: T.anything).returns(::RSpec::Matchers::BuiltIn::Has) }
    def have_key(key); end # rubocop:disable Naming/PredicatePrefix -- RSpec's dynamic matcher name.
  end
end
