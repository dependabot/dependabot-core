# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  class Job
    # Parsed representation of a dependency group from the job definition.
    #
    # Replaces the raw job hash with a typed struct so
    # downstream code gets compile-time checked field access instead of
    # hash key lookups that return T.untyped.
    #
    # Named DependencyGroupDefinition to avoid colliding with
    # Dependabot::DependencyGroup, the runtime grouping model this
    # definition is used to build.
    class DependencyGroupDefinition < T::ImmutableStruct
      extend T::Sig

      const :name, T.nilable(String)
      const :applies_to, T.nilable(String)
      RuleValue = T.type_alias { T.any(String, T::Array[String]) }

      const :rules, T.nilable(T::Hash[String, RuleValue])

      # Unexpected value types are coerced to nil rather than raising, so a
      # malformed entry degrades gracefully instead of crashing the job at
      # the parse boundary.
      sig { params(hash: T::Hash[String, Object]).returns(DependencyGroupDefinition) }
      def self.from_hash(hash)
        name = hash["name"]
        applies_to = hash["applies-to"]
        rules = hash["rules"]

        new(
          name: name.is_a?(String) ? name : nil,
          applies_to: applies_to.is_a?(String) ? applies_to : nil,
          rules: string_hash(rules)
        )
      end

      # The wire format of this group definition, used when reporting job
      # errors back to the service.
      sig { returns(T::Hash[String, Object]) }
      def to_h
        {
          "name" => name,
          "applies-to" => applies_to,
          "rules" => rules
        }.compact
      end

      sig { params(value: T.nilable(Object)).returns(T.nilable(T::Hash[String, RuleValue])) }
      def self.string_hash(value)
        return unless value.is_a?(Hash)

        valid = T.let(true, T::Boolean)
        result = T.let({}, T::Hash[String, RuleValue])
        value.each do |raw_key, raw_value|
          key = T.cast(raw_key, Object)
          unless key.is_a?(String)
            valid = false
            next
          end

          parsed_value = rule_value(T.cast(raw_value, Object))
          unless parsed_value
            valid = false
            next
          end

          result[key] = parsed_value
        end
        result if valid
      end
      private_class_method :string_hash

      sig { params(value: Object).returns(T.nilable(RuleValue)) }
      def self.rule_value(value)
        return value if value.is_a?(String)
        return unless value.is_a?(Array) && value.all?(String)

        value.map { |entry| T.cast(entry, String) }
      end
      private_class_method :rule_value
    end
  end
end
