# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/package/release_cooldown_options"

module Dependabot
  class Job
    # Parsed representation of cooldown settings from the job definition.
    class CooldownDefinition < T::ImmutableStruct
      extend T::Sig

      const :default_days, T.nilable(Integer)
      const :semver_major_days, T.nilable(Integer)
      const :semver_minor_days, T.nilable(Integer)
      const :semver_patch_days, T.nilable(Integer)
      const :include, T::Array[String], default: []
      const :exclude, T::Array[String], default: []

      sig { params(hash: T::Hash[String, Object]).returns(CooldownDefinition) }
      def self.from_hash(hash)
        new(
          default_days: optional_integer(hash["default-days"], "default-days"),
          semver_major_days: optional_integer(hash["semver-major-days"], "semver-major-days"),
          semver_minor_days: optional_integer(hash["semver-minor-days"], "semver-minor-days"),
          semver_patch_days: optional_integer(hash["semver-patch-days"], "semver-patch-days"),
          include: string_array(hash["include"], "include"),
          exclude: string_array(hash["exclude"], "exclude")
        )
      end

      sig { params(default_days: Integer).returns(Dependabot::Package::ReleaseCooldownOptions) }
      def to_options(default_days:)
        Dependabot::Package::ReleaseCooldownOptions.new(
          default_days: self.default_days.nil? ? default_days : self.default_days,
          semver_major_days: semver_major_days || 0,
          semver_minor_days: semver_minor_days || 0,
          semver_patch_days: semver_patch_days || 0,
          include: include,
          exclude: exclude
        )
      end

      sig { params(value: T.nilable(Object), key: String).returns(T.nilable(Integer)) }
      def self.optional_integer(value, key)
        return if value.nil?
        raise TypeError, "#{key} must be an integer" unless value.is_a?(Integer)

        value
      end
      private_class_method :optional_integer

      sig { params(value: T.nilable(Object), key: String).returns(T::Array[String]) }
      def self.string_array(value, key)
        return [] if value.nil?
        raise TypeError, "#{key} must be an array of strings" unless value.is_a?(Array) && value.all?(String)

        value.map { |entry| T.cast(entry, String) }
      end
      private_class_method :string_array
    end
  end
end
