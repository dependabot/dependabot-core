# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency_graphers"
require "dependabot/dependency_graphers/base"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/package_manager"
require "dependabot/npm_and_yarn/helpers"

module Dependabot
  module NpmAndYarn
    class DependencyGrapher < Dependabot::DependencyGraphers::Base
      extend T::Sig

      require_relative "dependency_grapher/lockfile_generator"

      sig { override.returns(Dependabot::DependencyFile) }
      def relevant_dependency_file
        # An ephemerally generated lockfile should not be reported as the
        # relevant file since it doesn't exist in the repository.
        return package_json if @ephemeral_lockfile_generated

        lockfile || package_json
      end

      sig { override.void }
      def prepare!
        if lockfile.nil?
          Dependabot.logger.info("No lockfile found, generating ephemeral lockfile for dependency graphing")
          generate_ephemeral_lockfile!
          emit_missing_lockfile_warning! if @ephemeral_lockfile_generated
        end
        super
      end

      private

      sig { returns(Dependabot::DependencyFile) }
      def package_json
        return T.must(@package_json) if defined?(@package_json)

        T.must(
          @package_json = T.let(
            T.must(dependency_files.find { |f| f.name.end_with?(NpmAndYarn::MANIFEST_FILENAME) }),
            T.nilable(Dependabot::DependencyFile)
          )
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def lockfile
        return @lockfile if defined?(@lockfile)

        @lockfile = T.let(
          dependency_files.find do |f|
            f.name.end_with?(
              NpmPackageManager::LOCKFILE_NAME,
              YarnPackageManager::LOCKFILE_NAME,
              PNPMPackageManager::LOCKFILE_NAME
            )
          end,
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T::Hash[String, T.untyped]) }
      def parsed_package_json
        @parsed_package_json ||= T.let(
          JSON.parse(T.must(package_json.content)),
          T.nilable(T::Hash[String, T.untyped])
        )
      rescue JSON::ParserError
        {}
      end

      sig { returns(T::Hash[Symbol, T.nilable(Dependabot::DependencyFile)]) }
      def lockfiles_hash
        {
          npm: dependency_files.find { |f| f.name.end_with?(NpmPackageManager::LOCKFILE_NAME) },
          yarn: dependency_files.find { |f| f.name.end_with?(YarnPackageManager::LOCKFILE_NAME) },
          pnpm: dependency_files.find { |f| f.name.end_with?(PNPMPackageManager::LOCKFILE_NAME) }
        }
      end

      sig { returns(String) }
      def detected_package_manager
        @detected_package_manager ||= T.let(
          PackageManagerDetector.new(
            lockfiles_hash,
            parsed_package_json
          ).detect_package_manager,
          T.nilable(String)
        )
      end

      sig { void }
      def generate_ephemeral_lockfile!
        generator = LockfileGenerator.new(
          dependency_files: dependency_files,
          package_manager: detected_package_manager,
          credentials: file_parser.credentials
        )

        ephemeral_lockfile = generator.generate

        # Inject the ephemeral lockfile into the dependency files
        # so the file parser can use it
        inject_ephemeral_lockfile(ephemeral_lockfile)
        @ephemeral_lockfile_generated = T.let(true, T.nilable(T::Boolean))

        Dependabot.logger.info(
          "Successfully generated ephemeral #{ephemeral_lockfile.name} for dependency graphing"
        )
      rescue StandardError => e
        errored_fetching_subdependencies!
        @subdependency_error = e
        Dependabot.logger.warn(
          "Failed to generate ephemeral lockfile: #{e.message}. " \
          "Dependency versions may not be resolved."
        )
      end

      sig { params(ephemeral_lockfile: Dependabot::DependencyFile).void }
      def inject_ephemeral_lockfile(ephemeral_lockfile)
        dependency_files << ephemeral_lockfile

        # Clear our cached lockfile reference so it picks up the new one
        remove_instance_variable(:@lockfile) if instance_variable_defined?(:@lockfile)

        # Clear the FileParser's memoized lockfile references so it will
        # find the newly injected lockfile when parse is called
        file_parser.instance_variable_set(:@package_lock, nil)
        file_parser.instance_variable_set(:@yarn_lock, nil)
        file_parser.instance_variable_set(:@pnpm_lock, nil)
        # Also clear the lockfile_parser which parses lockfile content
        file_parser.instance_variable_set(:@lockfile_parser, nil)
        # Also clear the package_manager_helper which caches lockfile info
        file_parser.instance_variable_set(:@package_manager_helper, nil)
      end

      sig { void }
      def emit_missing_lockfile_warning!
        Dependabot.logger.warn(
          "No lockfile was found in this repository. " \
          "Dependabot generated a temporary lockfile to determine exact dependency versions.\n\n" \
          "To ensure consistent builds and security scanning, we recommend committing your " \
          "package-lock.json (npm), yarn.lock (yarn), or pnpm-lock.yaml (pnpm). " \
          "Without a committed lockfile, resolved dependency versions may change between scans " \
          "due to new package releases."
        )
      end

      sig { override.params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def fetch_subdependencies(dependency)
        dependency_names = @dependencies.map(&:name)
        package_relationships.fetch(dependency.name, []).select { |child| dependency_names.include?(child) }
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def package_relationships
        @package_relationships ||= T.let(
          fetch_package_relationships,
          T.nilable(T::Hash[String, T::Array[String]])
        )
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_package_relationships
        return fetch_npm_lock_relationships if npm_lockfile
        # TODO: Implement yarn and pnpm relationship extraction
        {}
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def npm_lockfile
        return @npm_lockfile if defined?(@npm_lockfile)

        @npm_lockfile = T.let(
          dependency_files.find { |f| f.name.end_with?(NpmPackageManager::LOCKFILE_NAME) },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_npm_lock_relationships
        parsed = JSON.parse(T.must(T.must(npm_lockfile).content))
        packages = parsed.fetch("packages", {})

        packages.each_with_object({}) do |(path, details), rels|
          next if path.empty? # skip root package entry
          next unless details.is_a?(Hash)

          parent_name = T.must(path.split("node_modules/").last)
          children = details.fetch("dependencies", {}).keys

          next if children.empty?

          rels[parent_name] = children
        end
      rescue JSON::ParserError
        {}
      end

      sig { override.params(_dependency: Dependabot::Dependency).returns(String) }
      def purl_pkg_for(_dependency)
        "npm"
      end

      # npm packages use the package name as-is for the purl
      sig { params(dependency: Dependabot::Dependency).returns(String) }
      def purl_name_for(dependency)
        # Handle scoped packages: @scope/name -> %40scope/name (URL encoded @)
        dependency.name.sub(/^@/, "%40")
      end
    end
  end
end

Dependabot::DependencyGraphers.register("npm_and_yarn", Dependabot::NpmAndYarn::DependencyGrapher)
