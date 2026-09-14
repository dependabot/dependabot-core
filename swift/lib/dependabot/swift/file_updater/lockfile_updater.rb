# typed: strong
# frozen_string_literal: true

require "dependabot/file_updaters/base"
require "dependabot/shared_helpers"
require "dependabot/logger"
require "dependabot/errors"
require "json"
require "sorbet-runtime"

module Dependabot
  module Swift
    class FileUpdater < Dependabot::FileUpdaters::Base
      class LockfileUpdater
        extend T::Sig

        sig do
          params(
            dependency: Dependabot::Dependency,
            manifest: Dependabot::DependencyFile,
            lockfile: T.nilable(Dependabot::DependencyFile),
            repo_contents_path: String,
            credentials: T::Array[Dependabot::Credential],
            target_version: T.nilable(String)
          )
            .void
        end
        def initialize(dependency:, manifest:, lockfile:, repo_contents_path:, credentials:, target_version: nil)
          @dependency = dependency
          @manifest = manifest
          @lockfile = lockfile
          @repo_contents_path = repo_contents_path
          @credentials = credentials
          @target_version = target_version
        end

        sig { returns(String) }
        def updated_lockfile_content
          SharedHelpers.in_a_temporary_repo_directory(manifest.directory, repo_contents_path) do
            File.write(manifest.name, manifest.content)

            SharedHelpers.with_git_configured(credentials: credentials) do
              try_lockfile_update(T.must(dependency.metadata_string(:identity)))

              generated_lockfile_content = File.read("Package.resolved")
              merge_lockfile_content(generated_lockfile_content)
            end
          end
        end

        private

        sig { params(generated_content: String).returns(String) }
        def merge_lockfile_content(generated_content)
          return generated_content unless lockfile&.content

          original = parse_lockfile(T.must(T.must(lockfile).content))
          generated = parse_lockfile(generated_content)
          original_schema = schema_version(original)
          generated_schema = schema_version(generated)
          pins = pins_for(original, original_schema)
          generated_pins = pins_for(generated, generated_schema)
          identity = T.must(dependency.metadata_string(:identity))
          generated_pin = find_pin(generated_pins, generated_schema, identity)

          return generated_content unless generated_pin

          original_pin = find_pin(pins, original_schema, identity)
          return T.must(T.must(lockfile).content) if original_pin && pin_state(original_pin) == pin_state(generated_pin)

          replace_pin(pins, original_schema, identity, convert_pin(generated_pin, generated_schema, original_schema))
          update_origin_hash(original, generated)
          serialize_lockfile(original)
        rescue JSON::ParserError => e
          raise Dependabot::DependencyFileNotParseable.new("Package.resolved", e.message)
        end

        sig { params(lockfile_content: T::Hash[String, Object]).returns(Integer) }
        def schema_version(lockfile_content)
          version = lockfile_content["version"]
          raise JSON::ParserError, "missing lockfile version" unless version.is_a?(Integer)

          version
        end

        sig do
          params(
            pins: T::Array[T::Hash[String, Object]],
            schema: Integer,
            identity: String
          ).returns(T.nilable(T::Hash[String, Object]))
        end
        def find_pin(pins, schema, identity)
          pins.find { |pin| pin_identity(pin, schema) == identity.downcase }
        end

        sig { params(content: String).returns(T::Hash[String, Object]) }
        def parse_lockfile(content)
          T.cast(JSON.parse(content), T::Hash[String, Object])
        end

        sig do
          params(
            lockfile_content: T::Hash[String, Object],
            schema_version: T.nilable(Object)
          ).returns(T::Array[T::Hash[String, Object]])
        end
        def pins_for(lockfile_content, schema_version)
          pins = if schema_version == 1
                   object = T.cast(lockfile_content["object"], T.nilable(T::Hash[String, Object]))
                   T.cast(object["pins"], T.nilable(T::Array[T::Hash[String, Object]])) if object
                 else
                   T.cast(lockfile_content["pins"], T.nilable(T::Array[T::Hash[String, Object]]))
                 end

          raise JSON::ParserError, "missing pins array" unless pins

          pins
        end

        sig { params(pin: T::Hash[String, Object], schema_version: Integer).returns(String) }
        def pin_identity(pin, schema_version)
          identity_key = schema_version == 1 ? "package" : "identity"
          identity = pin[identity_key]
          raise JSON::ParserError, "missing pin identity" unless identity.is_a?(String)

          identity.downcase
        end

        sig { params(pin: T::Hash[String, Object]).returns(T::Hash[String, Object]) }
        def pin_state(pin)
          state = pin["state"]
          raise JSON::ParserError, "missing pin state" unless state.is_a?(Hash)

          state
        end

        sig do
          params(
            pins: T::Array[T::Hash[String, Object]],
            schema: Integer,
            identity: String,
            replacement: T::Hash[String, Object]
          ).void
        end
        def replace_pin(pins, schema, identity, replacement)
          index = pins.index { |pin| pin_identity(pin, schema) == identity.downcase }
          index ? pins[index] = replacement : pins << replacement
        end

        sig do
          params(
            original: T::Hash[String, Object],
            generated: T::Hash[String, Object]
          ).void
        end
        def update_origin_hash(original, generated)
          if generated.key?("originHash")
            original["originHash"] = generated["originHash"]
          else
            original.delete("originHash")
          end
        end

        sig { params(lockfile_content: T::Hash[String, Object]).returns(String) }
        def serialize_lockfile(lockfile_content)
          JSON.pretty_generate(
            lockfile_content,
            indent: "  ",
            space: " ",
            space_before: " ",
            object_nl: "\n",
            array_nl: "\n"
          ) + "\n"
        end

        sig do
          params(
            pin: T::Hash[String, Object],
            source_schema: Integer,
            target_schema: Integer
          ).returns(T::Hash[String, Object])
        end
        def convert_pin(pin, source_schema, target_schema)
          return pin if source_schema == target_schema

          source_identity_key = source_schema == 1 ? "package" : "identity"
          source_url_key = source_schema == 1 ? "repositoryURL" : "location"
          target_identity_key = target_schema == 1 ? "package" : "identity"
          target_url_key = target_schema == 1 ? "repositoryURL" : "location"

          {
            target_identity_key => pin.fetch(source_identity_key),
            target_url_key => pin.fetch(source_url_key),
            "state" => pin_state(pin)
          }
        rescue KeyError => e
          raise JSON::ParserError, "missing pin field: #{e.key}"
        end

        sig { params(dependency_name: String).void }
        def try_lockfile_update(dependency_name)
          if target_version
            SharedHelpers.run_shell_command(
              "swift package resolve #{dependency_name} --version #{target_version}",
              fingerprint: "swift package resolve <dependency_name> --version <target_version>"
            )
          else
            SharedHelpers.run_shell_command(
              "swift package update #{dependency_name}",
              fingerprint: "swift package update <dependency_name>"
            )
          end
        rescue SharedHelpers::HelperSubprocessFailed => e
          # This class is not only used for final lockfile updates, but for
          # checking resolvability. So resolvability errors here are expected in
          # certain situations and will result in `no_update_possible` outcomes.
          # That said, since we're swallowing all errors we at least log them to ease debugging.
          Dependabot.logger.info("Lockfile failed to be updated due to error:\n#{e.message}")
        end

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :lockfile

        sig { returns(String) }
        attr_reader :repo_contents_path

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T.nilable(String)) }
        attr_reader :target_version
      end
    end
  end
end
