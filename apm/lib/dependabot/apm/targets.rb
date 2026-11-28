# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "yaml"

module Dependabot
  module Apm
    # Reads the harness targets APM selects for an install: the ones a manifest
    # declares, and the ones the APM CLI supports.
    module Targets
      extend T::Sig

      MANIFEST_KEYS = %w(targets target).freeze
      # APM folds the deprecated `all` token, alone or beside other names, into
      # an omitted target selection.
      LEGACY_ALL_TARGET = "all"

      # Whether `apm.yml` declares `targets:` (or the older `target:`), in which
      # case APM uses them rather than auto-detecting harnesses.
      sig { params(manifest_content: String).returns(T::Boolean) }
      def self.declared_in_manifest?(manifest_content)
        manifest = YAML.safe_load(manifest_content, aliases: true)
        return false unless manifest.is_a?(Hash)

        MANIFEST_KEYS.any? do |key|
          tokens = target_tokens(manifest[key])
          tokens.any? && !tokens.include?(LEGACY_ALL_TARGET)
        end
      rescue Psych::Exception
        false
      end

      # A target value as APM reads it: a list, or a string that may hold
      # comma-separated names.
      sig { params(value: T.nilable(Object)).returns(T::Array[String]) }
      def self.target_tokens(value)
        return [] if value.nil?

        raw = value.is_a?(Array) ? value.map(&:to_s) : value.to_s.split(",")
        raw.map(&:strip).reject(&:empty?)
      end
      private_class_method :target_tokens

      # The target names in `apm targets --json --all` output.
      sig { params(json: String).returns(T::Array[String]) }
      def self.supported(json)
        rows = JSON.parse(json)
        return [] unless rows.is_a?(Array)

        rows.filter_map do |row|
          target = row["target"] if row.is_a?(Hash)
          target if target.is_a?(String)
        end
      rescue JSON::ParserError
        []
      end
    end
  end
end
