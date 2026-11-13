# typed: strong
# frozen_string_literal: true

require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/package/npm_package_manager_config"
require "dependabot/npm_and_yarn/native_helpers"
require "dependabot/npm_and_yarn/version"

module Dependabot
  module NpmAndYarn
    class NodeVersionManager
      extend T::Sig

      SCRIPT = "/opt/node-version-manager"
      TOOLS_DIRECTORY = "/opt/node-tools"
      ObjectHash = T.type_alias { T::Hash[String, Object] }

      sig { returns(T::Array[String]) }
      attr_reader :requirements

      sig { returns(T.nilable(String)) }
      attr_reader :preferred_requirement

      sig do
        params(file: DependencyFile, version_file: T.nilable(DependencyFile))
          .returns([T::Array[String], T.nilable(String)])
      end
      def self.requirements_from_file(file, version_file: nil)
        manifest = object_hash(T.cast(JSON.parse(T.must(file.content)), Object), "package.json")
        config = Dependabot::Package::NpmPackageManagerConfig.from_package_json(manifest)
        version = version_file ? version_file_requirement(version_file) : config.engines&.fetch("node", nil)
        requirements = [version].compact.reject { |value| value.strip.empty? }
        runtime, optional = runtime_requirement(manifest)
        requirements << runtime if runtime && !optional
        [requirements, optional ? runtime : nil]
      rescue JSON::ParserError
        raise DependencyFileNotParseable, file.path
      end

      sig { params(file: DependencyFile).returns(String) }
      def self.version_file_requirement(file)
        content = T.must(file.content)
        if file.name == ".nvmrc"
          lines = content.lines.map { |line| line.sub(/#.*/, "").strip }
                         .reject { |line| line.empty? || line.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\s*=/) }
          unless lines.length == 1
            raise MisconfiguredTooling.new("Node.js", "#{file.name} must contain exactly one version")
          end

          return T.must(lines.first)
        end

        version = content.strip
        raise MisconfiguredTooling.new("Node.js", "#{file.name} must contain a version") if version.empty?

        version
      end
      private_class_method :version_file_requirement

      sig { params(manifest: ObjectHash).returns([T.nilable(String), T::Boolean]) }
      def self.runtime_requirement(manifest)
        entries = runtime_entries(manifest)
        return [nil, false] if entries.empty?

        optional = %w(ignore warn).include?(T.must(entries.last)["onFail"].to_s)
        entries = entries.select { |entry| entry["name"] == "node" }
        return [nil, optional] if entries.any? { |entry| !entry.key?("version") }

        versions = entries.map { |entry| runtime_version(entry) }
        return [nil, optional] if versions.any? { |version| version.strip.empty? }

        [versions.empty? ? nil : versions.join(" || "), optional]
      end
      private_class_method :runtime_requirement

      sig { params(entry: ObjectHash).returns(String) }
      def self.runtime_version(entry)
        version = entry["version"]
        raise MisconfiguredTooling.new("Node.js", "devEngines.runtime.version must be a string") unless
          version.is_a?(String)

        version
      end
      private_class_method :runtime_version

      sig { params(manifest: ObjectHash).returns(T::Array[ObjectHash]) }
      def self.runtime_entries(manifest)
        dev_engines = manifest["devEngines"]
        return [] unless dev_engines

        runtime = object_hash(dev_engines, "devEngines")["runtime"]
        return [] unless runtime

        (runtime.is_a?(Array) ? runtime : [runtime]).map do |entry|
          object_hash(T.cast(entry, Object), "devEngines.runtime")
        end
      end
      private_class_method :runtime_entries

      sig { params(value: Object, field: String).returns(ObjectHash) }
      def self.object_hash(value, field)
        raise MisconfiguredTooling.new("Node.js", "#{field} must be an object") unless value.is_a?(Hash)

        value
      end
      private_class_method :object_hash

      sig { params(requirements: T::Array[String], preferred_requirement: T.nilable(String)).void }
      def initialize(requirements, preferred_requirement: nil)
        @requirements = requirements
        @preferred_requirement = preferred_requirement
        @resolved = T.let(false, T::Boolean)
        @bin_directory = T.let(nil, T.nilable(String))
      end

      sig { returns(T.nilable(String)) }
      def bin_directory
        return @bin_directory if @resolved

        @bin_directory = resolve
        @resolved = true
        @bin_directory
      end

      private

      sig { returns(T.nilable(String)) }
      def resolve
        requirements = resolve_aliases(@requirements)
        current_version = SharedHelpers.run_shell_command("node -v", fingerprint: "node -v").strip.delete_prefix("v")
        current = Version.new(current_version)
        available = T.let(nil, T.nilable(T::Array[Version]))

        if @preferred_requirement
          satisfied, directory, available = resolve_preference(requirements, current, @preferred_requirement)
          return directory if satisfied
        end

        return if matching_version([current], requirements)

        version = matching_version((available || available_versions).reverse, requirements)
        unless version
          raise ToolVersionNotSupported.new("Node.js", @requirements.join(" AND "), "published Node.js releases")
        end

        Dependabot.logger.info("Installing Node.js #{version} to satisfy #{@requirements.join(' AND ')}")
        File.dirname(install(version))
      end

      sig do
        params(requirements: T::Array[String], current: Version, preference: String)
          .returns([T::Boolean, T.nilable(String), T.nilable(T::Array[Version])])
      end
      def resolve_preference(requirements, current, preference)
        available = T.let(nil, T.nilable(T::Array[Version]))
        preferred = requirements + resolve_aliases([preference])
        return [true, nil, nil] if matching_version([current], preferred)

        available = available_versions
        candidate = matching_version(available.reverse, preferred)
        if candidate
          Dependabot.logger.info("Installing Node.js #{candidate} to satisfy #{preference}")
          return [true, File.dirname(install(candidate)), available]
        end
        Dependabot.logger.warn("No Node.js release satisfies preferred runtime #{preference} and other requirements")
        [false, nil, available]
      rescue SharedHelpers::HelperSubprocessFailed, MisconfiguredTooling => e
        Dependabot.logger.warn("Could not satisfy preferred Node.js runtime #{preference}: #{e.message}")
        [false, nil, available]
      end

      sig { params(version: Version).returns(String) }
      def install(version)
        node = SharedHelpers.run_shell_command(
          ["bash", SCRIPT, "install", version.to_s],
          fingerprint: "nvm install <version>",
          stderr_to_stdout: false
        ).strip
        unless node.match?(%r{\A/.+/node\z})
          raise MisconfiguredTooling.new("Node.js", "nvm returned an invalid executable path: #{node.inspect}")
        end

        node
      end

      sig { params(requirements: T::Array[String]).returns(T::Array[String]) }
      def resolve_aliases(requirements)
        requirements.map do |requirement|
          if requirement.match?(%r{\A(?:node|stable|lts/(?:\*|[a-zA-Z0-9-]+))\z})
            resolve_alias(requirement)
          else
            requirement
          end
        end
      end

      sig { params(name: String).returns(String) }
      def resolve_alias(name)
        output = SharedHelpers.run_shell_command(
          ["bash", SCRIPT, "resolve", name],
          fingerprint: "nvm version-remote <alias>"
        ).strip
        unless output.match?(/\Av\d+\.\d+\.\d+\z/)
          raise MisconfiguredTooling.new("Node.js", "nvm could not resolve Node.js alias #{name.inspect}: #{output}")
        end

        output.delete_prefix("v")
      end

      sig { params(versions: T::Array[Version], requirements: T::Array[String]).returns(T.nilable(Version)) }
      def matching_version(versions, requirements)
        result = SharedHelpers.run_helper_subprocess(
          command: "node #{File.join(NativeHelpers.native_helpers_root, 'dist', 'node-version.js')}",
          function: "npm:matchNodeVersions",
          args: [versions.map(&:to_s), requirements]
        )
        unless result.is_a?(Hash)
          raise MisconfiguredTooling.new("Node.js", "Node.js semver helper returned an invalid response")
        end

        validate_invalid_requirement(T.let(result.fetch("invalidRequirement"), T.nilable(Object)), requirements)

        version = T.let(result.fetch("version"), T.nilable(Object))
        return if version.nil?
        raise MisconfiguredTooling.new("Node.js", "Node.js semver helper returned an invalid version") unless
          version.is_a?(String) && versions.any? { |candidate| candidate.to_s == version }

        Version.new(version)
      rescue KeyError
        raise MisconfiguredTooling.new("Node.js", "Node.js semver helper returned an invalid response")
      end

      sig { params(invalid: T.nilable(Object), requirements: T::Array[String]).void }
      def validate_invalid_requirement(invalid, requirements)
        return unless invalid
        unless invalid.is_a?(String) && requirements.include?(invalid)
          raise MisconfiguredTooling.new("Node.js", "Node.js semver helper returned an invalid response")
        end

        raise MisconfiguredTooling.new("Node.js", "Invalid Node.js runtime requirement: #{invalid}")
      end

      sig { returns(T::Array[Version]) }
      def available_versions
        output = SharedHelpers.run_shell_command(
          ["bash", SCRIPT, "list"],
          fingerprint: "nvm ls-remote"
        )
        output.lines.filter_map do |line|
          match = line.match(/\A\s*v(?<version>\d+\.\d+\.\d+)(?:\s|\z)/)
          Version.new(T.must(match[:version])) if match
        end.sort
      end
    end
  end
end
