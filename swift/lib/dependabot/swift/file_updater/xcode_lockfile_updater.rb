# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/swift/file_updater"
require "dependabot/swift/url_helpers"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
      # Updates Xcode-managed Package.resolved files in-place without running
      # the Swift CLI. This is used for Xcode SPM projects that don't have a
      # Package.swift manifest file.
      #
      # Preserves the original schema version (v1/v2/v3) and minimizes changes
      # to the file structure to produce clean diffs.
      class XcodeLockfileUpdater
        extend T::Sig

        SUPPORTED_VERSIONS = T.let([1, 2, 3].freeze, T::Array[Integer])

        # Maps schema version to the JSON keys used for each pin field
        PIN_KEYS = T.let(
          {
            1 => { url: "repositoryURL", identity: "package", pins_path: %w(object pins) },
            2 => { url: "location", identity: "identity", pins_path: ["pins"] },
            3 => { url: "location", identity: "identity", pins_path: ["pins"] }
          }.freeze,
          T::Hash[Integer, T::Hash[Symbol, T.untyped]]
        )

        sig do
          params(
            resolved_file: Dependabot::DependencyFile,
            dependencies: T::Array[Dependabot::Dependency]
          ).void
        end
        def initialize(resolved_file:, dependencies:)
          @resolved_file = resolved_file
          @dependencies = dependencies
        end

        sig { returns(String) }
        def updated_lockfile_content
          content = resolved_file.content
          unless content
            raise Dependabot::DependencyFileNotParseable.new(
              resolved_file.name,
              "#{resolved_file.name} has no content"
            )
          end

          parsed = parse_json(content)
          schema_version = detect_schema_version(parsed)
          keys = T.must(PIN_KEYS[schema_version])

          update_pins(parsed, schema_version, keys)

          # Use JSON.pretty_generate to match Xcode's output format:
          # - 2-space indentation
          # - space before colon (e.g., "key" : "value")
          JSON.pretty_generate(
            parsed,
            indent: "  ",
            space: " ",
            space_before: " ",
            object_nl: "\n",
            array_nl: "\n"
          ) + "\n"
        end

        # Returns true if any dependency in the given file needs updating
        sig { returns(T::Boolean) }
        def lockfile_changed?
          dependencies_for_file.any?
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :resolved_file

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { params(content: String).returns(T::Hash[String, T.untyped]) }
        def parse_json(content)
          JSON.parse(content)
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
            schema_version: Integer,
            keys: T::Hash[Symbol, T.untyped]
          ).void
        end
        def update_pins(parsed, schema_version, keys)
          pins_path = T.cast(keys[:pins_path], T::Array[String])
          pins = dig_pins(parsed, pins_path)

          unless pins.is_a?(Array)
            raise Dependabot::DependencyFileNotParseable.new(
              resolved_file.name,
              "#{resolved_file.name} is missing the expected 'pins' array " \
              "(schema version #{schema_version})"
            )
          end

          dependencies_for_file.each do |dep|
            update_pin_for_dependency(pins, dep, keys, schema_version)
          end
        end

        sig do
          params(
            parsed: T::Hash[String, T.untyped],
            path: T::Array[String]
          ).returns(T.untyped)
        end
        def dig_pins(parsed, path)
          # Navigate nested hash using path keys
          # Path is either ["object", "pins"] for v1 or ["pins"] for v2/v3
          current = T.let(parsed, T.untyped)
          path.each do |key|
            break unless current.is_a?(Hash)

            current = current[key]
          end
          current
        end

        sig do
          params(
            pins: T::Array[T::Hash[String, T.untyped]],
            dependency: Dependabot::Dependency,
            keys: T::Hash[Symbol, T.untyped],
            schema_version: Integer
          ).void
        end
        def update_pin_for_dependency(pins, dependency, keys, schema_version)
          pin = find_pin_for_dependency(pins, dependency, keys, schema_version)
          return unless pin

          state = pin["state"]
          return unless state.is_a?(Hash)

          source = dependency.requirements.first&.dig(:source)
          new_version = dependency.version
          new_ref = source&.dig(:ref)

          # Update version if we have a new one
          if new_version
            state["version"] = new_version
            # When updating to a new version, update revision if provided in source
            # The ref from source is typically the git SHA corresponding to the version tag
            state["revision"] = new_ref if new_ref && looks_like_sha?(new_ref)
          elsif new_ref
            # Revision-only update (no version, just SHA)
            state["revision"] = new_ref
            state.delete("version")
          end
        end

        # Checks if a string looks like a git SHA (40 hex characters)
        sig { params(str: String).returns(T::Boolean) }
        def looks_like_sha?(str)
          str.match?(/\A[0-9a-f]{40}\z/i)
        end

        sig do
          params(
            pins: T::Array[T::Hash[String, T.untyped]],
            dependency: Dependabot::Dependency,
            keys: T::Hash[Symbol, T.untyped],
            schema_version: Integer
          ).returns(T.nilable(T::Hash[String, T.untyped]))
        end
        def find_pin_for_dependency(pins, dependency, keys, schema_version)
          identity_key = T.cast(keys[:identity], String)
          url_key = T.cast(keys[:url], String)
          identity = dependency.metadata[:identity]

          pins.find do |pin|
            pin_identity = pin[identity_key]
            # v1 uses display name which may be mixed case
            pin_identity = pin_identity&.downcase if schema_version == 1

            if identity && pin_identity == identity
              true
            else
              # Fall back to URL matching
              pin_url = pin[url_key]
              next false unless pin_url.is_a?(String)

              normalized_pin_url = SharedHelpers.scp_to_standard(pin_url)
              pin_name = UrlHelpers.normalize_name(normalized_pin_url)

              pin_name == dependency.name
            end
          end
        end

        # Returns only the dependencies that are relevant to this resolved file
        sig { returns(T::Array[Dependabot::Dependency]) }
        def dependencies_for_file
          @dependencies_for_file ||= T.let(
            dependencies.select do |dep|
              dep.requirements.any? do |req|
                # Match if the requirement file is the resolved file itself
                # or if the requirement file is a pbxproj in the same xcodeproj
                req_file = req[:file]
                if req_file == resolved_file.name
                  true
                elsif req_file&.include?(".xcodeproj/")
                  # Extract the xcodeproj dir from both files and compare
                  req_xcodeproj = extract_xcodeproj_dir(req_file)
                  resolved_xcodeproj = extract_xcodeproj_dir(resolved_file.name)
                  req_xcodeproj && req_xcodeproj == resolved_xcodeproj
                else
                  false
                end
              end
            end,
            T.nilable(T::Array[Dependabot::Dependency])
          )
        end

        # Extracts the .xcodeproj directory from a file path.
        # e.g. "MyApp.xcodeproj/project.xcworkspace/.../Package.resolved" -> "MyApp.xcodeproj"
        sig { params(path: String).returns(T.nilable(String)) }
        def extract_xcodeproj_dir(path)
          match = path.match(%r{^(.*?\.xcodeproj)/})
          match&.captures&.first
        end
      end
    end
  end
end
