# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency_file"

module Dependabot
  module Maven
    module Shared
      # Interface implemented by the ecosystem-specific PropertyValueFinder
      # classes (Gradle, SBT) that SharedPropertyValueUpdater delegates to.
      # Living in the shared namespace keeps the abstract return type load-safe:
      # each ecosystem gem loads Maven's shared code without loading its sibling.
      module PropertyValueFinding
        extend T::Sig
        extend T::Helpers

        interface!

        sig do
          abstract
            .params(property_name: String, callsite_buildfile: Dependabot::DependencyFile)
            .returns(T.nilable(T::Hash[Symbol, String]))
        end
        def property_details(property_name:, callsite_buildfile:); end
      end
    end
  end
end
