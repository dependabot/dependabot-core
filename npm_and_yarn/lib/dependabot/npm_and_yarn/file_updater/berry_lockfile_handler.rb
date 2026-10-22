# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "yaml"
require "json"

require "dependabot/npm_and_yarn/file_updater"
require "dependabot/experiments"
require "dependabot/npm_and_yarn/file_parser/yarn_lock"
require "dependabot/npm_and_yarn/helpers"
require "dependabot/npm_and_yarn/requirement"

# Handles yarn berry lockfile manipulation — parsing descriptors, finding
# entries, and rewriting keys from exact versions back to ranges. This is
# the berry equivalent of yarn classic's replace-lockfile-declaration.ts.
module Dependabot
  module NpmAndYarn
    class FileUpdater < Dependabot::FileUpdaters::Base
      class BerryLockfileHandler
        extend T::Sig

        sig do
          params(
            yarn_lock: Dependabot::DependencyFile,
            dependency: Dependabot::Dependency,
            target_version: String,
            env: T.nilable(T::Hash[String, String]),
            install_args: String
          ).returns(T.nilable(String))
        end
        def self.update_subdependency(
          yarn_lock:, dependency:, target_version:, env: nil, install_args: Helpers.yarn_berry_args
        )
          return unless Dependabot::Experiments.enabled?(:enable_yarn_berry_conflicting_dependencies)

          current_version = dependency.previous_version || dependency.version
          return unless current_version

          versions = FileParser::YarnLock.new(yarn_lock).versions_by_requirement(dependency.name)
          # A truthy unchanged version prevents callers from attempting an unscoped fallback.
          return current_version unless versions.value?(current_version)

          descriptors = subdependency_descriptors(versions, current_version)
          return if descriptors.empty?

          validate_subdependency_descriptors!(descriptors, dependency.name, current_version, target_version)

          resolutions = descriptors.to_h do |descriptor|
            [descriptor, subdependency_resolution(descriptor, dependency.name, target_version)]
          end
          resolution_command = Helpers.yarn_major_version == 2 ? "install" : "install --mode=update-lockfile"
          with_temporary_resolutions(yarn_lock, resolutions) do
            Helpers.run_yarn_command(resolution_command, fingerprint: "install", env: env)
            restore_subdependency_descriptors(
              yarn_lock: yarn_lock,
              dependency_name: dependency.name,
              target_version: target_version,
              descriptors: descriptors,
              original_versions: versions
            )
          end
          Helpers.run_yarn_command("install #{install_args}".strip, fingerprint: "install", env: env)
          target_version
        end

        sig { params(versions: T::Hash[String, String], current_version: String).returns(T::Array[String]) }
        def self.subdependency_descriptors(versions, current_version)
          versions.select do |descriptor, version|
            version == current_version && split_descriptor(descriptor).last&.start_with?("npm:")
          end.keys
        end
        private_class_method :subdependency_descriptors

        sig do
          params(
            descriptors: T::Array[String],
            dependency_name: String,
            current_version: String,
            target_version: String
          ).void
        end
        def self.validate_subdependency_descriptors!(descriptors, dependency_name, current_version, target_version)
          target = Version.new(target_version)
          descriptors.each do |descriptor|
            requirement = T.must(split_descriptor(descriptor).last)
                           .delete_prefix("npm:").delete_prefix("#{dependency_name}@")
            unless Requirement.requirements_array(requirement).any? { |range| range.satisfied_by?(target) }
              raise DependencyFileNotResolvable,
                    "Cannot update #{descriptor} from #{current_version} to #{target_version}: incompatible requirement"
            end
          end
        end
        private_class_method :validate_subdependency_descriptors!

        sig { params(descriptor: String, dependency_name: String, target_version: String).returns(String) }
        def self.subdependency_resolution(descriptor, dependency_name, target_version)
          reference = T.must(split_descriptor(descriptor).last)
          return "npm:#{dependency_name}@#{target_version}" if reference.start_with?("npm:#{dependency_name}@")

          "npm:#{target_version}"
        end
        private_class_method :subdependency_resolution

        sig do
          params(
            yarn_lock: Dependabot::DependencyFile,
            resolutions: T::Hash[String, String],
            _blk: T.proc.void
          ).void
        end
        def self.with_temporary_resolutions(yarn_lock, resolutions, &_blk)
          manifest_path = File.join(File.dirname(yarn_lock.name), "package.json")
          original_manifest = File.read(manifest_path)
          manifest = JSON.parse(original_manifest)
          manifest["resolutions"] = resolutions.merge(manifest.fetch("resolutions", {})) do |_key, temporary, _existing|
            temporary
          end
          begin
            File.write(manifest_path, JSON.pretty_generate(manifest))
            yield
          ensure
            File.write(manifest_path, original_manifest)
          end
        end
        private_class_method :with_temporary_resolutions

        sig do
          params(
            yarn_lock: Dependabot::DependencyFile,
            dependency_name: String,
            target_version: String,
            descriptors: T::Array[String],
            original_versions: T::Hash[String, String]
          ).void
        end
        def self.restore_subdependency_descriptors(
          yarn_lock:, dependency_name:, target_version:, descriptors:, original_versions:
        )
          parsed = parse(yarn_lock.name)
          raise DependencyFileNotResolvable, "Cannot parse updated #{yarn_lock.name}" unless parsed

          descriptor_groups = descriptors.group_by do |descriptor|
            name, = split_descriptor(descriptor)
            "#{name}@#{subdependency_resolution(descriptor, dependency_name, target_version)}"
          end
          descriptor_groups.each do |exact_descriptor, original_descriptors|
            key = parsed.keys.find { |entry| entry.to_s.split(", ").include?(exact_descriptor) }
            unless key
              verify_updated_subdependency_descriptors!(
                yarn_lock, dependency_name, target_version, original_descriptors
              )
              next
            end

            requirements = key.split(", ")
            requirements.delete(exact_descriptor) unless original_versions.key?(exact_descriptor)
            record = parsed.delete(key)
            parsed[(requirements | original_descriptors).sort.join(", ")] = record
          end
          File.write(yarn_lock.name, YAML.dump(parsed))
        end
        private_class_method :restore_subdependency_descriptors

        sig do
          params(
            yarn_lock: Dependabot::DependencyFile,
            dependency_name: String,
            target_version: String,
            descriptors: T::Array[String]
          ).void
        end
        def self.verify_updated_subdependency_descriptors!(yarn_lock, dependency_name, target_version, descriptors)
          updated_file = yarn_lock.dup
          updated_file.content = File.read(yarn_lock.name)
          versions = FileParser::YarnLock.new(updated_file).versions_by_requirement(dependency_name)
          return if descriptors.all? { |descriptor| versions[descriptor] == target_version }

          raise DependencyFileNotResolvable,
                "Missing updated Yarn resolution for #{dependency_name}@#{target_version}"
        end
        private_class_method :verify_updated_subdependency_descriptors!

        # Parses a yarn berry lockfile (YAML format). Returns nil if unparseable.
        sig { params(lockfile_path: String).returns(T.nilable(T::Hash[String, T.untyped])) }
        def self.parse(lockfile_path)
          return unless File.exist?(lockfile_path)

          parsed = YAML.safe_load_file(lockfile_path)
          parsed.is_a?(Hash) ? parsed : nil
        end

        # Checks if the parsed lockfile has the target version for a dependency.
        sig { params(parsed: T::Hash[String, T.untyped], dep_name: String, version: String).returns(T::Boolean) }
        def self.version_matches?(parsed, dep_name, version)
          parsed.any? do |key, value|
            next false unless value.is_a?(Hash)

            key.to_s.split(", ").any? { |part| split_descriptor(part)[0] == dep_name } &&
              value["version"] == version
          end
        end

        # Rewrites a lockfile descriptor key from exact version to range.
        # Example: "axios@npm:1.15.2" → "axios@npm:^1.15.2"
        # The resolved version, checksum, and dependencies remain unchanged.
        sig do
          params(
            lockfile_path: String,
            dep_name: String,
            version: String,
            requirement: String
          ).void
        end
        def self.replace_declaration(lockfile_path, dep_name, version, requirement)
          return unless File.exist?(lockfile_path)

          content = File.read(lockfile_path)
          parsed = parse(lockfile_path)
          return unless parsed

          exact_key = find_exact_key(parsed, dep_name, version)
          return unless exact_key

          protocol = extract_protocol(exact_key, dep_name)
          new_key = "#{dep_name}@#{protocol}#{requirement}"

          escaped = Regexp.escape(exact_key)
          File.write(lockfile_path, content.gsub(/^"#{escaped}":/m, "\"#{new_key}\":"))
        end

        # Finds the lockfile key containing the given dep name with exact version.
        # Handles composite keys (e.g., "a@npm:1.0, a@npm:^1.0").
        sig { params(parsed: T::Hash[String, T.untyped], dep_name: String, version: String).returns(T.nilable(String)) }
        def self.find_exact_key(parsed, dep_name, version)
          parsed.keys.find do |key|
            next false unless key.is_a?(String)

            key.split(", ").any? do |part|
              name, desc = split_descriptor(part)
              name == dep_name && (desc&.end_with?(version) || false)
            end
          end
        end

        # Splits a yarn berry descriptor into [package_name, version/range].
        # Handles scoped packages like @scope/pkg@npm:^1.0.0.
        sig { params(descriptor: String).returns([String, T.nilable(String)]) }
        def self.split_descriptor(descriptor)
          if descriptor.start_with?("@")
            at_index = descriptor.index("@", 1)
            return [descriptor, nil] unless at_index

            [T.must(descriptor[0...at_index]), descriptor[(at_index + 1)..]]
          else
            parts = descriptor.split("@", 2)
            [T.must(parts[0]), parts[1]]
          end
        end

        # Extracts the protocol prefix (e.g., "npm:") from a descriptor.
        sig { params(key: String, dep_name: String).returns(String) }
        def self.extract_protocol(key, dep_name)
          part = key.split(", ").find { |p| split_descriptor(p)[0] == dep_name }
          return "" unless part

          _, descriptor = split_descriptor(part)
          match = descriptor&.match(/^([a-z]+:)/)
          match ? T.must(match[1]) : ""
        end
      end
    end
  end
end
