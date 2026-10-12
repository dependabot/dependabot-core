# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/shared_helpers"
require "dependabot/bundler/version"
require "dependabot/bundler/update_checker"

module Dependabot
  module Bundler
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class VersionDetails < T::ImmutableStruct
        extend T::Sig

        class InvalidResult < SharedHelpers::HelperSubprocessFailed; end

        ObjectHash = T.type_alias { T::Hash[String, Object] }

        const :version, Dependabot::Bundler::Version
        const :ruby_version, T.nilable(String), default: nil
        const :fetcher, T.nilable(String), default: nil
        const :commit_sha, T.nilable(String), default: nil

        sig { params(result: Object).returns(VersionDetails) }
        def self.from_helper_result(result)
          fields = object_fields(result)
          new(
            version: parse_version(fields["version"]),
            ruby_version: optional_string(fields["ruby_version"], "ruby_version"),
            fetcher: optional_string(fields["fetcher"], "fetcher"),
            commit_sha: optional_string(fields["commit_sha"], "commit_sha")
          )
        end

        sig { params(value: Object).returns(ObjectHash) }
        def self.object_fields(value)
          invalid_result(" must be an object") unless value.is_a?(Hash)

          value.to_h do |raw_key, raw_value|
            key = T.cast(raw_key, Object)
            invalid_result(" keys must be strings") unless key.is_a?(String)

            [key, T.cast(raw_value, Object)]
          end
        end
        private_class_method :object_fields

        sig { params(value: Object).returns(Dependabot::Bundler::Version) }
        def self.parse_version(value)
          invalid_result(".version must be a string") unless value.is_a?(String)

          # Version.new's inherited signature returns the base class.
          T.cast(Dependabot::Bundler::Version.new(value), Dependabot::Bundler::Version)
        rescue ArgumentError
          invalid_result(".version must be a valid version")
        end
        private_class_method :parse_version

        sig { params(value: Object, field: String).returns(T.nilable(String)) }
        def self.optional_string(value, field)
          return if value.nil?
          return value if value.is_a?(String)

          invalid_result(".#{field} must be a string or nil")
        end
        private_class_method :optional_string

        sig { params(message: String).returns(T.noreturn) }
        def self.invalid_result(message)
          raise InvalidResult.new(
            message: "resolve_version result#{message}",
            error_class: "TypeError",
            error_context: { function: "resolve_version" }
          ),
                cause: nil
        end
        private_class_method :invalid_result
      end
    end
  end
end
