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

      # Whether `apm.yml` declares `targets:` (or the older `target:`), in which
      # case APM uses them rather than auto-detecting harnesses.
      sig { params(manifest_content: String).returns(T::Boolean) }
      def self.declared_in_manifest?(manifest_content)
        manifest = YAML.safe_load(manifest_content)
        return false unless manifest.is_a?(Hash)

        MANIFEST_KEYS.any? do |key|
          value = manifest[key]
          value.is_a?(String) ? !value.strip.empty? : value.is_a?(Array) && value.any?
        end
      rescue Psych::Exception
        false
      end

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
