# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/errors"
require "dependabot/git_commit_checker"
require "dependabot/logger"
require "dependabot/bun/dependency_files_filterer"
require "dependabot/bun/file_parser"
require "dependabot/bun/file_updater/npmrc_builder"
require "dependabot/bun/file_updater/package_json_preparer"
require "dependabot/bun/helpers"
require "dependabot/bun/native_helpers"
require "dependabot/bun/package_name"
require "dependabot/bun/requirement"
require "dependabot/bun/update_checker"
require "dependabot/bun/version"
require "dependabot/shared_helpers"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module Bun
    class UpdateChecker
      class VersionResolver
        extend T::Sig

        require_relative "latest_version_finder"

        TIGHTLY_COUPLED_MONOREPOS = T.let(
          {
            "vue" => %w(vue vue-template-compiler)
          }.freeze,
          T::Hash[String, T::Array[String]]
        )

        # Error message returned by `npm install` (for NPM 6):
        # react-dom@15.2.0 requires a peer of react@^15.2.0 \
        # but none is installed. You must install peer dependencies yourself.
        NPM6_PEER_DEP_ERROR_REGEX =
          /
            (?<requiring_dep>[^\s]+)\s
            requires\sa\speer\sof\s
            (?<required_dep>.+?)\sbut\snone\sis\sinstalled.
          /x

        # Error message returned by `npm install` (for NPM 8):
        # npm ERR! Could not resolve dependency:
        # npm ERR! peer react@"^16.14.0" from react-dom@16.14.0
        #
        # or with two semver constraints:
        # npm ERR! Could not resolve dependency:
        # npm ERR! peer @opentelemetry/api@">=1.0.0 <1.1.0" from @opentelemetry/context-async-hooks@1.0.1
        NPM8_PEER_DEP_ERROR_REGEX =
          /
            npm\s(?:WARN|ERR!)\sCould\snot\sresolve\sdependency:\n
            npm\s(?:WARN|ERR!)\speer\s(?<required_dep>\S+@\S+(\s\S+)?)\sfrom\s(?<requiring_dep>\S+@\S+)
          /x

        sig do
          params(
            dependency: Dependabot::Dependency,
            dependency_files: T::Array[Dependabot::DependencyFile],
            credentials: T::Array[Dependabot::Credential],
            latest_allowable_version: T.nilable(T.any(String, Gem::Version)),
            latest_version_finder: PackageLatestVersionFinder,
            repo_contents_path: T.nilable(String),
            dependency_group: T.nilable(Dependabot::DependencyGroup),
            raise_on_ignored: T::Boolean,
            update_cooldown: T.nilable(Dependabot::Package::ReleaseCooldownOptions)
          ).void
        end
        def initialize( # rubocop:disable Metrics/AbcSize
          dependency:,
          dependency_files:,
          credentials:,
          latest_allowable_version:,
          latest_version_finder:,
          repo_contents_path:,
          dependency_group: nil,
          raise_on_ignored: false,
          update_cooldown: nil
        )
          @dependency               = dependency
          @dependency_files         = dependency_files
          @credentials              = credentials
          @latest_allowable_version = latest_allowable_version
          @dependency_group = dependency_group

          @latest_version_finder = T.let({}, T::Hash[Dependabot::Dependency, PackageLatestVersionFinder])
          @latest_version_finder[dependency] = latest_version_finder
          @repo_contents_path = repo_contents_path
          @raise_on_ignored = raise_on_ignored
          @update_cooldown = update_cooldown

          @types_package = T.let(nil, T.nilable(Dependabot::Dependency))
          @original_package = T.let(nil, T.nilable(Dependabot::Dependency))
          @latest_types_package_version = T.let(nil, T.nilable(Dependabot::Version))
          @dependency_files_builder = T.let(nil, T.nilable(DependencyFilesBuilder))
          @resolve_latest_previous_version = T.let({}, T::Hash[Dependabot::Dependency, T.nilable(String)])
          @paths_requiring_update_check = T.let(nil, T.nilable(T::Array[String]))
          @top_level_dependencies = T.let(nil, T.nilable(T::Array[Dependabot::Dependency]))
          @old_peer_dependency_errors = T.let(
            nil, T.nilable(T::Array[T.any(T::Hash[String, T.nilable(String)], String)])
          )
          @peer_dependency_errors = T.let(nil, T.nilable(T::Array[T.any(T::Hash[String, T.nilable(String)], String)]))
        end

        sig { returns(T.nilable(T.any(String, Gem::Version))) }
        def latest_resolvable_version
          return latest_allowable_version if git_dependency?(dependency)
          return if part_of_tightly_locked_monorepo?
          return if types_update_available?
          return if original_package_update_available?

          return latest_allowable_version unless relevant_unmet_peer_dependencies.any?

          satisfying_versions.first
        end

        sig { returns(T::Boolean) }
        def latest_version_resolvable_with_full_unlock?
          return false if dependency_updates_from_full_unlock.nil?

          true
        end

        sig do
          params(
            updated_version: T.nilable(T.any(String, Gem::Version))
          ).returns(T.nilable(T.any(String, Gem::Version)))
        end
        def latest_resolvable_previous_version(updated_version)
          resolve_latest_previous_version(dependency, updated_version)
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { returns(T.nilable(T::Array[T::Hash[String, T.nilable(String)]])) }
        def dependency_updates_from_full_unlock
          return if git_dependency?(dependency)
          return updated_monorepo_dependencies if part_of_tightly_locked_monorepo?
          return if newly_broken_peer_reqs_from_dep.any?
          return if original_package_update_available?

          updates = [{
            dependency: dependency,
            version: latest_allowable_version,
            previous_version: latest_resolvable_previous_version(
              latest_allowable_version
            )
          }]
          newly_broken_peer_reqs_on_dep.each do |peer_req|
            dep_name = peer_req.fetch(:requiring_dep_name)
            dep = top_level_dependencies.find { |d| d.name == dep_name }

            # Can't handle reqs from sub-deps or git source deps (yet)
            return nil if dep.nil?
            return nil if git_dependency?(dep)

            updated_version =
              latest_version_of_dep_with_satisfied_peer_reqs(dep)
            return nil unless updated_version

            updates << {
              dependency: dep,
              version: updated_version,
              previous_version: resolve_latest_previous_version(
                dep, updated_version
              )
            }
          end
          updates += updated_types_dependencies if types_update_available?
          updates.uniq
        end
        # rubocop:enable Metrics/PerceivedComplexity

        private

        sig { returns(Dependabot::Dependency) }
        attr_reader :dependency
        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files
        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials
        sig { returns(T.nilable(T.any(String, Gem::Version))) }
        attr_reader :latest_allowable_version
        sig { returns(T.nilable(String)) }
        attr_reader :repo_contents_path
        sig { returns(T.nilable(Dependabot::DependencyGroup)) }
        attr_reader :dependency_group
        sig { returns(T.nilable(Dependabot::Package::ReleaseCooldownOptions)) }
        attr_reader :update_cooldown
        sig { returns(T::Boolean) }
        attr_reader :raise_on_ignored

        sig { params(dep: Dependabot::Dependency) .returns(PackageLatestVersionFinder) }
        def latest_version_finder(dep)
          @latest_version_finder[dep] ||=
            PackageLatestVersionFinder.new(
              dependency: dep,
              dependency_files: dependency_files,
              credentials: credentials,
              cooldown_options: update_cooldown,
              ignored_versions: [],
              security_advisories: [],
              raise_on_ignored: raise_on_ignored
            )
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig do
          params(
            dep: Dependabot::Dependency,
            updated_version: T.nilable(T.any(String, Gem::Version))
          ).returns(T.nilable(String))
        end
        def resolve_latest_previous_version(dep, updated_version)
          return dep.version if dep.version

          @resolve_latest_previous_version[dep] ||= begin
            relevant_versions = latest_version_finder(dependency)
                                .possible_previous_versions_with_details
                                .map(&:first)
            reqs = dep.requirements.filter_map { |r| r[:requirement] }
                      .map { |r| requirement_class.requirements_array(r) }

            # Pick the lowest version from the max possible version from all
            # requirements. This matches the logic when combining the same
            # dependency in DependencySet from multiple manifest files where we
            # pick the lowest version from the duplicates.
            latest_previous_version = reqs.flat_map do |req|
              relevant_versions.select do |version|
                req.any? { |r| r.satisfied_by?(version) }
              end.max
            end.min&.to_s

            # Handle cases where the latest resolvable previous version is the
            # latest version. This often happens if you don't have lockfiles and
            # have requirements update strategy set to bump_versions, where an
            # update might go from ^1.1.1 to ^1.1.2 (both resolve to 1.1.2).
            if updated_version.to_s == latest_previous_version
              nil
            else
              latest_previous_version
            end
          end
        end
        # rubocop:enable Metrics/PerceivedComplexity

        sig { returns(T::Boolean) }
        def part_of_tightly_locked_monorepo?
          monorepo_dep_names =
            TIGHTLY_COUPLED_MONOREPOS.values
                                     .find { |deps| deps.include?(dependency.name) }
          return false unless monorepo_dep_names

          deps_to_update =
            top_level_dependencies
            .select { |d| monorepo_dep_names.include?(d.name) }

          deps_to_update.count > 1
        end

        sig { returns(T::Array[T::Hash[String, T.nilable(String)]]) }
        def updated_monorepo_dependencies
          monorepo_dep_names =
            TIGHTLY_COUPLED_MONOREPOS.values
                                     .find { |deps| deps.include?(dependency.name) }

          deps_to_update =
            top_level_dependencies
            .select { |d| monorepo_dep_names&.include?(d.name) }

          updates = []
          deps_to_update.each do |dep|
            next if git_dependency?(dep)
            next if dep.version &&
                    version_class.new(dep.version) >= latest_allowable_version

            updated_version =
              latest_version_finder(dep)
              .possible_versions
              .find { |v| v == latest_allowable_version }
            next unless updated_version

            updates << {
              dependency: dep,
              version: updated_version,
              previous_version: resolve_latest_previous_version(
                dep, updated_version
              )
            }
          end

          updates
        end

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def types_package
          return @types_package if @types_package

          @types_package = begin
            types_package_name = PackageName.new(dependency.name).types_package_name
            top_level_dependencies.find { |d| types_package_name.to_s == d.name } if types_package_name
          end
          @types_package
        end

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def original_package
          return @original_package if @original_package

          @original_package = begin
            original_package_name = PackageName.new(dependency.name).library_name
            top_level_dependencies.find { |d| original_package_name.to_s == d.name } if original_package_name
          end
          @original_package
        end

        sig { returns(T.nilable(Dependabot::Version)) }
        def latest_types_package_version
          types_pkg = types_package
          return unless types_pkg

          return @latest_types_package_version if @latest_types_package_version

          @latest_types_package_version = latest_version_finder(types_pkg).latest_version_from_registry
          @latest_types_package_version
        end

        sig { returns(T::Boolean) }
        def types_update_available?
          types_pkg = types_package
          return false unless types_pkg

          latest_types_version = latest_types_package_version
          return false unless latest_types_version

          latest_allowable_ver = latest_allowable_version
          return false unless latest_allowable_ver.is_a?(Version) && latest_allowable_ver.backwards_compatible_with?(
            T.unsafe(latest_types_version)
          )

          return false unless version_class.correct?(types_pkg.version)

          current_types_package_version = version_class.new(types_pkg.version)

          return false unless current_types_package_version < latest_types_version

          true
        end

        sig { returns(T::Boolean) }
        def original_package_update_available?
          original_pack = original_package
          return false unless original_pack

          return false unless version_class.correct?(original_pack.version)

          original_package_version = version_class.new(original_pack.version)

          latest_version = latest_version_finder(original_pack).latest_version_from_registry

          # If the latest version is within the scope of the current requirements,
          # latest_version will be nil. In such cases, there is no update available.
          return false if latest_version.nil?

          original_package_version < latest_version
        end

        sig { returns(T::Array[T::Hash[String, T.nilable(String)]]) }
        def updated_types_dependencies
          [{
            dependency: types_package,
            version: latest_types_package_version,
            previous_version: resolve_latest_previous_version(
              T.must(types_package), T.cast(latest_types_package_version, Gem::Version)
            )
          }]
        end

        sig { returns(T::Array[T.any(T::Hash[String, T.nilable(String)], String)]) }
        def peer_dependency_errors
          return @peer_dependency_errors if @peer_dependency_errors

          @peer_dependency_errors = fetch_peer_dependency_errors(version: latest_allowable_version)
          @peer_dependency_errors
        end

        sig { returns(T::Array[T.any(T::Hash[String, T.nilable(String)], String)]) }
        def old_peer_dependency_errors
          return @old_peer_dependency_errors if @old_peer_dependency_errors

          version = version_for_dependency(dependency)

          @old_peer_dependency_errors = fetch_peer_dependency_errors(version: version)
          @old_peer_dependency_errors
        end

        sig do
          params(
            version: T.nilable(T.any(String, Gem::Version))
          ).returns(T::Array[T.any(T::Hash[String, T.nilable(String)], String)])
        end
        def fetch_peer_dependency_errors(version:)
          # TODO: Add all of the error handling that the FileUpdater does
          # here (since problematic repos will be resolved here before they're
          # seen by the FileUpdater)
          base_dir = T.must(dependency_files.first).directory
          SharedHelpers.in_a_temporary_repo_directory(base_dir, repo_contents_path) do
            dependency_files_builder.write_temporary_dependency_files

            paths_requiring_update_check.flat_map do |path|
              run_checker(path: path, version: version)
            end.compact
          end
        rescue SharedHelpers::HelperSubprocessFailed
          # Fall back to allowing the version through. Whatever error
          # occurred should be properly handled by the FileUpdater. We
          # can slowly migrate error handling to this class over time.
          []
        end

        sig { params(message: String).returns(T::Array[T::Hash[String, T.nilable(String)]]) }
        def handle_peer_dependency_errors(message)
          errors = []
          if message.match?(NPM6_PEER_DEP_ERROR_REGEX)
            message.scan(NPM6_PEER_DEP_ERROR_REGEX) do
              errors << Regexp.last_match&.named_captures
            end
          elsif message.match?(NPM8_PEER_DEP_ERROR_REGEX)
            message.scan(NPM8_PEER_DEP_ERROR_REGEX) do
              errors << T.must(Regexp.last_match).named_captures
            end
          else
            raise
          end
          errors
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def unmet_peer_dependencies
          peer_dependency_errors
            .map { |captures| error_details_from_captures(captures) }
        end

        sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
        def old_unmet_peer_dependencies
          old_peer_dependency_errors
            .map { |captures| error_details_from_captures(captures) }
        end

        sig do
          params(captures: T.any(T::Hash[String, T.nilable(String)], String))
            .returns(T::Hash[Symbol, T.nilable(String)])
        end
        def error_details_from_captures(captures)
          return {} unless captures.is_a?(Hash)

          required_dep_captures  = captures.fetch("required_dep")
          requiring_dep_captures = captures.fetch("requiring_dep")
          return {} unless required_dep_captures && requiring_dep_captures

          {
            requirement_name: required_dep_captures.sub(/@[^@]+$/, ""),
            requirement_version: required_dep_captures.split("@").last&.delete('"'),
            requiring_dep_name: requiring_dep_captures.sub(/@[^@]+$/, "")
          }
        end

        sig { returns(T::Array[T::Hash[Symbol, T.nilable(String)]]) }
        def relevant_unmet_peer_dependencies # rubocop:disable Metrics/PerceivedComplexity
          relevant_unmet_peer_dependencies =
            unmet_peer_dependencies.select do |dep|
              dep[:requirement_name] == dependency.name ||
                dep[:requiring_dep_name] == dependency.name
            end

          unless dependency_group.nil?
            # Ignore unmet peer dependencies that are in the dependency group because
            # the update is also updating those dependencies.
            relevant_unmet_peer_dependencies.reject! do |dep|
              dependency_group&.dependencies&.any? do |group_dep|
                dep[:requirement_name] == group_dep.name ||
                  dep[:requiring_dep_name] == group_dep.name
              end
            end
          end

          return [] if relevant_unmet_peer_dependencies.empty?

          # Prune out any pre-existing warnings
          relevant_unmet_peer_dependencies.reject do |issue|
            old_unmet_peer_dependencies.any? do |old_issue|
              old_issue.slice(:requirement_name, :requiring_dep_name) ==
                issue.slice(:requirement_name, :requiring_dep_name)
            end
          end
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { returns(T::Array[T.any(String, Gem::Version)]) }
        def satisfying_versions
          latest_version_finder(dependency)
            .possible_versions_with_details
            .select do |versions_with_details|
              version, details = versions_with_details
              next false unless satisfies_peer_reqs_on_dep?(T.unsafe(version))
              next true unless details["peerDependencies"]
              next true if version == version_for_dependency(dependency)

              details["peerDependencies"].all? do |dep, req|
                dep = top_level_dependencies.find { |d| d.name == dep }
                next false unless dep
                next git_dependency?(dep) if req.include?("/")

                reqs = requirement_class.requirements_array(req)
                next false unless version_for_dependency(dep)

                reqs.any? { |r| r.satisfied_by?(version_for_dependency(dep)) }
              rescue Gem::Requirement::BadRequirementError
                false
              end
            end.map do |versions_with_details| # rubocop:disable Style/MultilineBlockChain
              # Return just the version
              version, = versions_with_details
              version
            end
        end

        # rubocop:enable Metrics/PerceivedComplexity

        sig { params(version: T.nilable(T.any(String, Gem::Version))).returns(T::Boolean) }
        def satisfies_peer_reqs_on_dep?(version)
          newly_broken_peer_reqs_on_dep.all? do |peer_req|
            req = peer_req.fetch(:requirement_version)

            # Git requirements can't be satisfied by a version
            next false if req&.include?("/")

            reqs = requirement_class.requirements_array(req)
            reqs.any? { |r| r.satisfied_by?(version) }
          rescue Gem::Requirement::BadRequirementError
            false
          end
        end

        sig { params(dep: Dependabot::Dependency).returns(T.nilable(T.any(String, Gem::Version))) }
        def latest_version_of_dep_with_satisfied_peer_reqs(dep) # rubocop:disable Metrics/PerceivedComplexity
          dependency_version = version_for_dependency(dep)
          version_with_detail =
            latest_version_finder(dep)
            .possible_versions_with_details
            .find do |version_details|
              version, details = version_details

              next false unless !dependency_version || version > dependency_version
              next true unless details["peerDependencies"]

              details["peerDependencies"].all? do |peer_dep_name, req|
                # Can't handle multiple peer dependencies
                next false unless peer_dep_name == dependency.name
                next git_dependency?(dependency) if req.include?("/")

                reqs = requirement_class.requirements_array(req)

                reqs.any? { |r| r.satisfied_by?(latest_allowable_version) }
              rescue Gem::Requirement::BadRequirementError
                false
              end
            end
          version_with_detail.is_a?(Array) ? version_with_detail.first : version_with_detail
        end

        sig { params(dep: Dependabot::Dependency).returns(T::Boolean) }
        def git_dependency?(dep)
          # ignored_version/raise_on_ignored are irrelevant.
          GitCommitChecker
            .new(dependency: dep, credentials: credentials)
            .git_dependency?
        end

        sig { returns(T::Array[T::Hash[Symbol, T.nilable(String)]]) }
        def newly_broken_peer_reqs_on_dep
          relevant_unmet_peer_dependencies
            .select { |dep| dep[:requirement_name] == dependency.name }
        end

        sig { returns(T::Array[T::Hash[Symbol, T.nilable(String)]]) }
        def newly_broken_peer_reqs_from_dep
          relevant_unmet_peer_dependencies
            .select { |dep| dep[:requiring_dep_name] == dependency.name }
        end

        sig do
          params(
            lockfiles: T::Array[Dependabot::DependencyFile],
            path: String
          ).returns(T::Array[Dependabot::DependencyFile])
        end
        def lockfiles_for_path(lockfiles:, path:)
          lockfiles.select do |lockfile|
            File.dirname(lockfile.name) == File.dirname(path)
          end
        end

        sig do
          params(
            path: String,
            version: T.nilable(T.any(String, Gem::Version))
          ).returns(T.nilable(T.any(T::Hash[String, T.untyped], String, T::Array[T::Hash[String, T.untyped]])))
        end
        def run_checker(path:, version:)
          bun_lockfiles = lockfiles_for_path(lockfiles: dependency_files_builder.bun_locks, path: path)
          return run_bun_checker(path: path, version: version) if bun_lockfiles.any?

          root_bun_lock = dependency_files_builder.root_bun_lock
          run_bun_checker(path: path, version: version) if root_bun_lock
        rescue SharedHelpers::HelperSubprocessFailed => e
          handle_peer_dependency_errors(e.message)
        end

        sig do
          params(
            path: String,
            version: T.nilable(T.any(String, Gem::Version))
          ).returns(T.untyped)
        end
        def run_bun_checker(path:, version:)
          SharedHelpers.with_git_configured(credentials: credentials) do
            Dir.chdir(path) do
              Helpers.run_bun_command(
                "update #{dependency.name}@#{version} --save-text-lockfile",
                fingerprint: "update <dependency_name>@<version> --save-text-lockfile"
              )
            end
          end
        end

        sig do
          params(
            version: T.nilable(T.any(String, Gem::Version))
          ).returns(String)
        end
        def version_install_arg(version:)
          git_source = dependency.requirements.find { |req| req[:source] && req[:source][:type] == "git" }

          if git_source
            "#{dependency.name}@#{git_source[:source][:url]}##{version}"
          else
            "#{dependency.name}@#{version}"
          end
        end

        sig do
          params(
            requirements: T::Array[T::Hash[Symbol, T.untyped]],
            path: String
          ).returns(T::Array[T::Hash[Symbol, T.untyped]])
        end
        def requirements_for_path(requirements, path)
          return requirements if path.to_s == "."

          requirements.filter_map do |r|
            next unless r[:file].start_with?("#{path}/")

            r.merge(file: r[:file].gsub(/^#{Regexp.quote("#{path}/")}/, ""))
          end
        end

        # Top level dependencies are required in the peer dep checker
        # to fetch the manifests for all top level deps which may contain
        # "peerDependency" requirements
        sig { returns(T::Array[Dependabot::Dependency]) }
        def top_level_dependencies
          return @top_level_dependencies if @top_level_dependencies

          @top_level_dependencies = Bun::FileParser.new(
            dependency_files: dependency_files,
            source: nil,
            credentials: credentials
          ).parse.select(&:top_level?)
          @top_level_dependencies
        end

        sig { returns(T::Array[String]) }
        def paths_requiring_update_check
          return @paths_requiring_update_check if @paths_requiring_update_check

          @paths_requiring_update_check =
            DependencyFilesFilterer.new(
              dependency_files: dependency_files,
              updated_dependencies: [dependency]
            ).paths_requiring_update_check
          @paths_requiring_update_check
        end

        sig { returns(DependencyFilesBuilder) }
        def dependency_files_builder
          return @dependency_files_builder if @dependency_files_builder

          @dependency_files_builder =
            DependencyFilesBuilder.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials
            )
          @dependency_files_builder
        end

        sig { params(dep: Dependabot::Dependency).returns(T.nilable(T.any(String, Gem::Version))) }
        def version_for_dependency(dep)
          return version_class.new(dep.version) if dep.version && version_class.correct?(dep.version)

          dep.requirements.filter_map { |r| r[:requirement] }
             .reject { |req_string| req_string.start_with?("<") }
             .select { |req_string| req_string.match?(version_regex) }
             .map { |req_string| req_string.match(version_regex) }
             .select { |version| version_class.correct?(version.to_s) }
             .map { |version| version_class.new(version.to_s) }
             .max
        end

        sig { returns(T.class_of(Dependabot::Version)) }
        def version_class
          dependency.version_class
        end

        sig { returns(T.class_of(Dependabot::Requirement)) }
        def requirement_class
          dependency.requirement_class
        end

        sig { returns(String) }
        def version_regex
          Dependabot::Bun::Version::VERSION_PATTERN
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
