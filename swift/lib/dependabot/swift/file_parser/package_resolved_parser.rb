# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/swift/file_parser"
require "dependabot/swift/url_helpers"

module Dependabot
  module Swift
    class FileParser < Dependabot::FileParsers::Base
      class PackageResolvedParser
        extend T::Sig

        SUPPORTED_VERSIONS = T.let([1, 2, 3].freeze, T::Array[Integer])

        # Maps schema version to the JSON keys used for each pin field
        PIN_KEYS = T.let(
          {
            1 => { url: "repositoryURL", identity: "package", state: "state" },
            2 => { url: "location", identity: "identity", state: "state" },
            3 => { url: "location", identity: "identity", state: "state" }
          }.freeze,
          T::Hash[Integer, T::Hash[Symbol, String]]
        )

        sig { params(resolved_file: Dependabot::DependencyFile).void }
        def initialize(resolved_file)
          @resolved_file = resolved_file
        end

        sig { returns(T::Array[Dependabot::Dependency]) }
        def parse
          parsed = parse_json
          schema_version = detect_schema_version(parsed)
          pins = extract_pins(parsed, schema_version)

          pins.filter_map { |pin| build_dependency(pin, schema_version) }
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :resolved_file

        sig { returns(T::Hash[String, T.untyped]) }
        def parse_json
          JSON.parse(T.must(resolved_file.content))
        rescue JSON::ParserError => e
          raise Dependabot::DependencyFileNotParseable.new(
            resolved_file.name,
            "#{resolved_file.name} is not valid JSON: #{e.message}"
          )
        end

        sig { params(parsed: T::Hash[String, T.untyped]).returns(Integer) }
        def detect_schema_version(parsed)
          version = parsed["version"]

          unless version.is_a?(Integer) && SUPPORTED_VERSIONS.include?(version)
            raise Dependabot::DependencyFileNotParseable.new(
              resolved_file.name,
              "#{resolved_file.name} has unsupported schema version: #{version.inspect}. " \
              "Supported versions: #{SUPPORTED_VERSIONS.join(', ')}"
            )
          end

          version
        end

        sig do
          params(
            parsed: T::Hash[String, T.untyped],
            schema_version: Integer
          ).returns(T::Array[T::Hash[String, T.untyped]])
        end
        def extract_pins(parsed, schema_version)
          pins = if schema_version == 1
                   parsed.dig("object", "pins")
                 else
                   # v2 and v3 use the same top-level "pins" key
                   parsed["pins"]
                 end

          unless pins.is_a?(Array)
            raise Dependabot::DependencyFileNotParseable.new(
              resolved_file.name,
              "#{resolved_file.name} is missing the expected 'pins' array " \
              "(schema version #{schema_version})"
            )
          end

          pins
        end

        sig do
          params(
            pin: T::Hash[String, T.untyped],
            schema_version: Integer
          ).returns(T.nilable(Dependabot::Dependency))
        end
        def build_dependency(pin, schema_version)
          keys = T.must(PIN_KEYS[schema_version])
          url = pin[keys[:url]]
          return nil unless url.is_a?(String) && !url.empty?

          state = pin[keys[:state]] || {}
          identity = pin[keys[:identity]]
          # v1 uses a display name for "package"; normalize to lowercase like v2/v3 "identity"
          identity = identity&.downcase if schema_version == 1

          build_dependency_object(
            identity: identity,
            url: url,
            version: state["version"],
            revision: state["revision"],
            branch: state["branch"]
          )
        end

        sig do
          params(
            identity: T.nilable(String),
            url: String,
            version: T.nilable(String),
            revision: T.nilable(String),
            branch: T.nilable(String)
          ).returns(T.nilable(Dependabot::Dependency))
        end
        def build_dependency_object(identity:, url:, version:, revision:, branch:)
          normalized_url = SharedHelpers.scp_to_standard(url)
          name = UrlHelpers.normalize_name(normalized_url)
          ref = version || revision

          source = { type: "git", url: normalized_url, ref: ref, branch: branch }

          Dependency.new(
            name: name,
            version: version,
            package_manager: "swift",
            requirements: [{
              requirement: version ? "= #{version}" : nil,
              groups: ["dependencies"],
              file: resolved_file.name,
              source: source
            }],
            metadata: { identity: identity }
          )
        end
      end
    end
  end
end
