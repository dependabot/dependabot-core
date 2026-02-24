# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Python
    module Pep508DependencyEntry
      extend T::Sig

      NAME_REGEX = /\A([A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?(?:\[[^\]]+\])?)/
      DIRECT_REFERENCE_REGEX = /\A\s*[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?(?:\[[^\]]+\])?\s*@\s*\S+/

      sig { params(dep_entry: String).returns(T::Boolean) }
      def self.direct_reference?(dep_entry)
        dep_entry.split(";", 2).first.to_s.match?(DIRECT_REFERENCE_REGEX)
      end

      sig { params(dep_entry: T.untyped).returns(T.nilable(String)) }
      def self.name(dep_entry)
        dep_entry_string = case dep_entry
                           when String then dep_entry
                           else return
                           end
        return if direct_reference?(dep_entry_string)

        name_match = dep_entry_string.match(NAME_REGEX)
        return unless name_match

        T.must(name_match[1])
      end
    end
  end
end
