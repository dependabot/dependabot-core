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
require "dependabot/swift/xcode_file_helpers"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
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
            dependencies: T::Array[Dependabot::Dependency],
            workspace_files: T::Array[Dependabot::DependencyFile]
          ).void
        end
        def initialize(resolved_file:, dependencies:, workspace_files: [])
          @resolved_file = resolved_file
          @dependencies = dependencies
          @workspace_files = workspace_files
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

        sig { returns(T::Boolean) }
        def lockfile_changed?
          dependencies_for_file.any?
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :resolved_file

        sig { returns(T::Array[Dependabot::Dependency]) }
        attr_reader :dependencies

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :workspace_files

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

        sig { returns(T::Array[Dependabot::Dependency]) }
        def dependencies_for_file
          @dependencies_for_file ||= T.let(
            dependencies.select do |dep|
              dep.requirements.any? do |req|
                req_file_matches_resolved_scope?(req[:file])
              end
            end,
            T.nilable(T::Array[Dependabot::Dependency])
          )
        end

        sig { params(req_file: T.nilable(String)).returns(T::Boolean) }
        def req_file_matches_resolved_scope?(req_file)
          return false unless req_file
          return true if req_file == resolved_file.name
          return false unless req_file.include?(".xcodeproj/") || req_file.include?(".xcworkspace/")

          req_scope = extract_xcode_scope_dir(req_file)
          resolved_scope = extract_xcode_scope_dir(resolved_file.name)

          return true if req_scope && resolved_scope && req_scope == resolved_scope

          workspace_related_dependency?(req_file)
        end

        # Extracts the Xcode scope directory (.xcodeproj or .xcworkspace)
        # from a file path.
        sig { params(path: String).returns(T.nilable(String)) }
        def extract_xcode_scope_dir(path)
          XcodeFileHelpers.extract_xcode_scope_dir(path)
        end

        sig { params(req_file: T.nilable(String)).returns(T::Boolean) }
        def workspace_related_dependency?(req_file)
          return false unless req_file

          workspace_scope = extract_xcode_scope_dir(resolved_file.name)
          return false unless workspace_scope&.end_with?(".xcworkspace")
          return false unless req_file.include?(".xcodeproj/")

          req_scope = extract_xcode_scope_dir(req_file)
          return false unless req_scope

          referenced = referenced_project_scopes_for_workspace(workspace_scope)
          return referenced.include?(req_scope) if referenced.any?

          workspace_root = File.dirname(workspace_scope)

          if workspace_root == "."
            !req_scope.include?("/")
          else
            req_scope.start_with?("#{workspace_root}/")
          end
        end

        sig { params(workspace_scope: String).returns(T::Set[String]) }
        def referenced_project_scopes_for_workspace(workspace_scope)
          workspace_data_path = "#{workspace_scope}/contents.xcworkspacedata"
          file = workspace_files.find { |workspace_file| workspace_file.name == workspace_data_path }
          return Set.new unless file&.content

          project_refs = T.must(file.content).scan(/location\s*=\s*"(?:group:)?([^"\n]+\.xcodeproj)"/).flatten
          workspace_root = File.dirname(workspace_scope)

          Set.new(
            project_refs.map do |project_ref|
              if workspace_root == "."
                project_ref
              else
                File.join(workspace_root, project_ref)
              end
            end
          )
        end
      end
    end
  end
end
