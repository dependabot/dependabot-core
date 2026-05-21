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

      # Override to expand multi-version dependencies into separate resolved
      # dependency entries. When the same package exists at multiple versions
      # (e.g., is-number@6.0.0 direct + is-number@7.0.0 transitive), each
      # version gets its own entry with correct subdependency edges.
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
              direct: version_dep.top_level? || version_dep.metadata[:alias] != nil,
              runtime: version_dep.production?,
              dependencies: subdependency_purls_for(version_dep)
            )
          end
        end
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
        key = "#{dependency.name}@#{dependency.version}"
        package_relationships.fetch(key, [])
      end

      # Builds purl strings for subdependencies directly from the name@version
      # entries in package_relationships, without going through dependencies_by_name
      # which only holds one combined dep per package name.
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
        # For scoped packages (@scope/name@version), find the second @
        at_index = if name_version.start_with?("@")
                     name_version.index("@", 1)
                   else
                     name_version.index("@")
                   end
        return [name_version, nil] unless at_index

        version = name_version[(at_index + 1)..]
        version = nil if version.nil? || version.empty?
        [name_version[0...at_index], version]
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

            package_name = details["name"] || path.split("node_modules/").last
            version = details["version"]
            next if version.nil? || version.to_s.empty?

            resolved = resolve_npm_v3_children(packages, path, children)
            rels["#{package_name}@#{version}"] = resolved unless resolved.empty?
          end
        end

        # if packages isn't present, attempt a v1 fallback
        fetch_npm_v1_lock_relationships(parsed)
      end

      sig do
        params(
          packages: T::Hash[String, T.untyped],
          parent_path: String,
          children: T::Array[String]
        ).returns(T::Array[String])
      end
      def resolve_npm_v3_children(packages, parent_path, children)
        children.filter_map do |child_name|
          child_details = resolve_npm_child(packages, parent_path, child_name)
          next unless child_details

          child_version = child_details["version"]
          next if child_version.nil? || child_version.to_s.empty?

          # Use the "name" field for aliased packages (real name vs path alias)
          real_name = child_details["name"] || child_name
          "#{real_name}@#{child_version}"
        end
      end

      # Walks up the node_modules tree to resolve a child dependency,
      # matching Node.js module resolution behavior.
      sig do
        params(
          packages: T::Hash[String, T.untyped],
          parent_path: String,
          child_name: String
        ).returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def resolve_npm_child(packages, parent_path, child_name)
        # First check directly nested under parent
        candidate = "#{parent_path}/node_modules/#{child_name}"
        return packages[candidate] if packages.key?(candidate)

        # Walk up the tree: strip trailing node_modules/pkg segments
        segments = parent_path.split("node_modules/")
        segments.pop # remove the current package segment

        while segments.any?
          candidate = "#{segments.join('node_modules/')}node_modules/#{child_name}"
          return packages[candidate] if packages.key?(candidate)

          segments.pop
        end

        # Top-level fallback
        packages["node_modules/#{child_name}"]
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
          next if version.nil? || version.to_s.empty?

          children = resolve_npm_v1_children(nested)
          rels["#{name}@#{version}"] = children unless children.empty?
          rels.merge!(fetch_npm_v1_lock_relationships(details))
        end
      end

      sig { params(nested: T::Hash[String, T.untyped]).returns(T::Array[String]) }
      def resolve_npm_v1_children(nested)
        nested.filter_map do |child_name, child_details|
          next unless child_details.is_a?(Hash)

          child_version = child_details["version"]
          next if child_version.nil? || child_version.to_s.empty?

          "#{child_name}@#{child_version}"
        end
      end

      sig { returns(T::Hash[String, T::Array[String]]) }
      def fetch_yarn_lock_relationships
        parsed = FileParser::YarnLock.new(T.must(yarn_lockfile)).parsed

        parsed.each_with_object({}) do |(req, details), rels|
          next unless details.is_a?(Hash)

          version = details["version"]
          parent_name = T.must(req.split(/(?<=\w)\@/).first)
          children = details.fetch("dependencies", {})

          next if children.nil? || children.empty?

          key = "#{parent_name}@#{version}"
          resolved_children = resolve_yarn_children(children, parsed)

          rels[key] ||= []
          rels[key].concat(resolved_children).uniq!
        end
      end

      sig { params(children: T::Hash[String, String], parsed: T::Hash[String, T.untyped]).returns(T::Array[String]) }
      def resolve_yarn_children(children, parsed)
        children.filter_map do |child_name, child_req|
          version = resolve_yarn_child_version(child_name, child_req, parsed)
          "#{child_name}@#{version}" if version
        end
      end

      sig { params(child_name: String, child_req: String, parsed: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
      def resolve_yarn_child_version(child_name, child_req, parsed)
        # Try exact key first
        child_entry = parsed["#{child_name}@#{child_req}"]
        return child_entry["version"] if child_entry && child_entry["version"]

        # Yarn groups multiple requirements into single keys like "foo@^1.0.0, foo@^1.2.0"
        target_req = "#{child_name}@#{child_req}"
        grouped_match = parsed.find { |k, _| k.split(", ").include?(target_req) }
        return grouped_match.last["version"] if grouped_match && grouped_match.last["version"]

        # Fallback: find by name only if there's exactly one candidate
        candidates = parsed.select { |k, _| k.split(/(?<=\w)\@/).first == child_name }
        candidate = candidates.first
        candidate.last["version"] if candidates.size == 1 && candidate
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
          # Strip any peer metadata suffixes like "7.49.0(react@18.2.0)"
          resolved_children = children.filter_map do |child_name, child_version|
            clean_version = child_version.to_s.sub(/\(.*\)$/, "")
            next if clean_version.empty?

            "#{child_name}@#{clean_version}"
          end

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
