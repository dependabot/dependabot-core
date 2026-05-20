# typed: strict
# frozen_string_literal: true

require "json"
require "yaml"
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
        # Enable alias extraction for graph jobs so aliased packages appear
        # in the dependency graph for security scanning.
        file_parser.dealias_packages!

        if lockfile.nil?
          Dependabot.logger.info("No lockfile found, generating ephemeral lockfile for dependency graphing")
          generate_ephemeral_lockfile!
          emit_missing_lockfile_warning! if @ephemeral_lockfile_generated
        end
        super
      end

      # Override to expand multi-version dependencies (e.g., aliased + unaliased
      # versions of the same package) into separate resolved dependency entries.
      sig { override.returns(T::Hash[String, Dependabot::DependencyGraphers::ResolvedDependency]) }
      def resolved_dependencies
        prepare! unless prepared

        @dependencies.each_with_object({}) do |dep, resolved|
          all_versions = dep.metadata[:all_versions] || [dep]

          all_versions.each do |version_dep|
            purl = build_purl(version_dep)
            next if resolved.key?(purl)

            resolved[purl] = Dependabot::DependencyGraphers::ResolvedDependency.new(
              package_url: purl,
              direct: version_dep.top_level?,
              runtime: version_dep.production?,
              dependencies: subdependency_purls_for(version_dep)
            )
          end
        end
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
        # Look up by name@version to correctly distinguish subdependencies
        # for different versions of the same package (e.g., aliased + unaliased)
        key = "#{dependency.name}@#{dependency.version}"
        package_relationships.fetch(key, [])
      end

      # Builds purl strings for each subdependency of the given dependency.
      # Children in package_relationships are stored as "name@version" strings,
      # which we convert directly to purls.
      sig { params(dependency: Dependabot::Dependency).returns(T::Array[String]) }
      def subdependency_purls_for(dependency)
        return [] if errored_fetching_subdependencies

        key = "#{dependency.name}@#{dependency.version}"
        children = package_relationships.fetch(key, [])

        children.filter_map do |child_key|
          child_name, child_version = split_name_version(child_key)
          next unless child_name && child_version

          purl_name = child_name.sub(/^@/, "%40")
          format(PURL_TEMPLATE, type: "npm", name: purl_name, version: "@#{child_version}")
        end
      rescue StandardError => e
        errored_fetching_subdependencies!
        @subdependency_error = T.let(e, T.nilable(StandardError))
        Dependabot.logger.error("Error fetching subdependencies: #{e.message}")
        []
      end

      # Splits a "name@version" string, handling scoped packages like "@scope/pkg@1.0.0"
      sig { params(name_version: String).returns([T.nilable(String), T.nilable(String)]) }
      def split_name_version(name_version)
        if name_version.start_with?("@")
          # Scoped package: @scope/name@version
          at_index = name_version.index("@", 1)
          return [nil, nil] unless at_index

          [name_version[0...at_index], name_version[(at_index + 1)..]]
        else
          at_index = name_version.index("@")
          return [name_version, nil] unless at_index

          [name_version[0...at_index], name_version[(at_index + 1)..]]
        end
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
        case detected_package_manager
        when NpmPackageManager::NAME
          fetch_npm_lock_relationships
        when YarnPackageManager::NAME
          fetch_yarn_lock_relationships
        when PNPMPackageManager::NAME
          fetch_pnpm_lock_relationships
        else
          {}
        end
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def npm_lockfile
        return @npm_lockfile if defined?(@npm_lockfile)

        @npm_lockfile = T.let(
          dependency_files.find { |f| f.name.end_with?(NpmPackageManager::LOCKFILE_NAME) },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def yarn_lockfile
        return @yarn_lockfile if defined?(@yarn_lockfile)

        @yarn_lockfile = T.let(
          dependency_files.find { |f| f.name.end_with?(YarnPackageManager::LOCKFILE_NAME) },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T.nilable(Dependabot::DependencyFile)) }
      def pnpm_lockfile
        return @pnpm_lockfile if defined?(@pnpm_lockfile)

        @pnpm_lockfile = T.let(
          dependency_files.find { |f| f.name.end_with?(PNPMPackageManager::LOCKFILE_NAME) },
          T.nilable(Dependabot::DependencyFile)
        )
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_npm_lock_relationships
        parsed = JSON.parse(T.must(T.must(npm_lockfile).content))
        packages = parsed.fetch("packages", {})

        # v3/v2 lockfiles use a flat "packages" section
        if packages.is_a?(Hash) && !packages.empty?
          return packages.each_with_object({}) do |(path, details), rels|
            next if path.empty? # skip root package entry
            next unless details.is_a?(Hash)

            children = details.fetch("dependencies", {}).keys
            next if children.empty?

            # Use real package name (from details["name"]) for aliased packages
            package_name = details["name"] || path.split("node_modules/").last
            version = details["version"]
            key = "#{package_name}@#{version}"

            # Resolve each child to its name@version by looking up the installed
            # version in the packages section (nested first, then top-level)
            rels[key] = children.filter_map do |child_name|
              child_details = packages["#{path}/node_modules/#{child_name}"] ||
                              packages["node_modules/#{child_name}"]
              next child_name unless child_details

              child_real_name = child_details["name"] || child_name
              "#{child_real_name}@#{child_details['version']}"
            end
          end
        end

        # if packages isn't present, attempt a v1 fallback
        fetch_npm_v1_lock_relationships(parsed)
      end

      sig { params(parsed: T::Hash[String, T.untyped]).returns(T::Hash[String, T::Array[String]]) }
      def fetch_npm_v1_lock_relationships(parsed)
        dependencies = parsed.fetch("dependencies", {})
        return {} unless dependencies.is_a?(Hash)

        dependencies.each_with_object({}) do |(name, details), rels|
          next unless details.is_a?(Hash)

          nested = details.fetch("dependencies", nil)
          next unless nested.is_a?(Hash)

          version = details["version"]
          key = "#{name}@#{version}"

          # v1 nested dependencies have their version inline
          children = nested.filter_map do |child_name, child_details|
            next unless child_details.is_a?(Hash)

            "#{child_name}@#{child_details['version']}"
          end

          rels[key] = children unless children.empty?
          rels.merge!(fetch_npm_v1_lock_relationships(details))
        end
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_yarn_lock_relationships
        parsed = FileParser::YarnLock.new(T.must(yarn_lockfile)).parsed

        parsed.each_with_object({}) do |(req, details), rels|
          next unless details.is_a?(Hash)

          version = details["version"]
          children = details.fetch("dependencies", {})

          next if children.nil? || children.empty?

          # For alias entries like "my-fetch-factory@npm:fetch-factory@0.0.1",
          # extract the real package name
          parent_name = if req.match?(/@npm:(.+@(?!npm))/)
                          match = req.match(/@npm:(.+)$/)
                          T.must(match)[1]&.split(/(?<=\w)\@/)&.first
                        else
                          T.must(req.split(/(?<=\w)\@/).first)
                        end

          key = "#{parent_name}@#{version}"
          resolved_children = children.filter_map do |child_name, child_req|
            # Look up the child in the parsed lockfile to get its resolved version
            child_entry = parsed["#{child_name}@#{child_req}"]
            if child_entry && child_entry["version"]
              "#{child_name}@#{child_entry['version']}"
            else
              # Fall back to finding any entry for this package
              found = parsed.find { |k, _| k.split(/(?<=\w)\@/).first == child_name }
              found ? "#{child_name}@#{found.last['version']}" : nil
            end
          end

          rels[key] ||= []
          rels[key].concat(resolved_children).uniq!
        end
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_pnpm_lock_relationships
        parsed = YAML.safe_load(T.must(T.must(pnpm_lockfile).content)) || {}

        # v9+ uses "snapshots" for resolved dependency details; v6 uses "packages"
        entries = parsed.fetch("snapshots", nil) || parsed.fetch("packages", {})

        entries.each_with_object({}) do |(key, details), rels|
          next unless details.is_a?(Hash)

          # Keys are "/name@version" (v6) or "name@version" (v9)
          name_version = key.sub(%r{^/}, "")
          children = details.fetch("dependencies", {})

          next if children.nil? || children.empty?

          # Strip any pnpm suffix metadata (e.g., parenthesized peer dep info)
          name_version = name_version.sub(/\(.*\)$/, "")

          # pnpm dependencies are already resolved: {"name": "version"}
          resolved_children = children.map { |child_name, child_version| "#{child_name}@#{child_version}" }

          rels[name_version] ||= []
          rels[name_version].concat(resolved_children).uniq!
        end
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
