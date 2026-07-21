# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_requirement"

module Dependabot
  module Pub
    module SourceDescription
      extend T::Sig

      sig do
        params(
          source: T.nilable(Dependabot::DependencyRequirement::Details),
          key: String
        ).returns(T.nilable(String))
      end
      def self.value(source, key)
        return unless source

        description = source["description"] || source[:description]
        return unless description.is_a?(Hash)

        value = T.let(description[key] || description[key.to_sym], Object)
        value if value.is_a?(String)
      end
    end
  end
end
