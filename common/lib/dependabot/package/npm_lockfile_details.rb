# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/errors"

module Dependabot
  module Package
    class NpmLockfileDetails < T::ImmutableStruct
      extend T::Sig

      const :version, T.nilable(String), default: nil
      const :resolved, T.nilable(String), default: nil
      const :resolution, T.nilable(String), default: nil

      sig { params(value: Object, path: String, context: String).returns(NpmLockfileDetails) }
      def self.from_object(value, path:, context:)
        raise DependencyFileNotParseable.new(path, "#{context} must be an object") unless value.is_a?(Hash)

        new(
          version: optional_string(T.cast(value["version"], Object), path, "#{context}.version"),
          resolved: optional_string(T.cast(value["resolved"], Object), path, "#{context}.resolved"),
          resolution: optional_string(T.cast(value["resolution"], Object), path, "#{context}.resolution")
        )
      end

      sig { params(value: Object, path: String, field: String).returns(T.nilable(String)) }
      def self.optional_string(value, path, field)
        return if value.nil?
        return value if value.is_a?(String)

        raise DependencyFileNotParseable.new(path, "#{field} must be a string or nil")
      end
      private_class_method :optional_string
    end
  end
end
