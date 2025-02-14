# typed: true
# frozen_string_literal: true

module Dependabot
  module Javascript
    module Bun
      class UpdateChecker
        class VersionResolver # rubocop:disable Metrics/ClassLength
          extend T::Sig

          require_relative "latest_version_finder"

          TIGHTLY_COUPLED_MONOREPOS = {
            "vue" => %w(vue vue-template-compiler)
          }.freeze

          def initialize(dependency:, credentials:, dependency_files:,
                         latest_allowable_version:, latest_version_finder:, repo_contents_path:, dependency_group: nil)
            @dependency               = dependency
            @credentials              = credentials
            @dependency_files         = dependency_files
            @latest_allowable_version = latest_allowable_version
            @dependency_group = dependency_group

            @latest_version_finder = {}
            @latest_version_finder[dependency] = latest_version_finder
            @repo_contents_path = repo_contents_path
          end

          def latest_resolvable_version
            return latest_allowable_version if git_dependency?(dependency)
            return if part_of_tightly_locked_monorepo?
            return if types_update_available?
            return if original_package_update_available?

            return latest_allowable_version unless relevant_unmet_peer_dependencies.any?

            satisfying_versions.first
          end

          def latest_version_resolvable_with_full_unlock?
            return false if dependency_updates_from_full_unlock.nil?

            true
          end

          def latest_resolvable_previous_version(updated_version)
            resolve_latest_previous_version(dependency, updated_version)
          end

          # rubocop:disable Metrics/PerceivedComplexity
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
          attr_reader :credentials
          attr_reader :dependency_files
          attr_reader :latest_allowable_version
          attr_reader :repo_contents_path
          attr_reader :dependency_group

          def latest_version_finder(dep)
            @latest_version_finder[dep] ||=
              LatestVersionFinder.new(
                dependency: dep,
                credentials: credentials,
                dependency_files: dependency_files,
                ignored_versions: [],
                security_advisories: []
              )
          end

          # rubocop:disable Metrics/PerceivedComplexity
          def resolve_latest_previous_version(dep, updated_version)
            return dep.version if dep.version

            @resolve_latest_previous_version ||= {}
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

          def updated_monorepo_dependencies
            monorepo_dep_names =
              TIGHTLY_COUPLED_MONOREPOS.values
                                       .find { |deps| deps.include?(dependency.name) }

            deps_to_update =
              top_level_dependencies
              .select { |d| monorepo_dep_names.include?(d.name) }

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

          def types_package
            @types_package ||= begin
              types_package_name = Dependabot::Javascript::Shared::PackageName.new(dependency.name).types_package_name
              top_level_dependencies.find { |d| types_package_name.to_s == d.name } if types_package_name
            end
          end

          def original_package
            @original_package ||= begin
              original_package_name = Dependabot::Javascript::Shared::PackageName.new(dependency.name).library_name
              top_level_dependencies.find { |d| original_package_name.to_s == d.name } if original_package_name
            end
          end

          def latest_types_package_version
            @latest_types_package_version ||= latest_version_finder(types_package).latest_version_from_registry
          end

          def types_update_available?
            return false if types_package.nil?

            return false if latest_types_package_version.nil?

            return false unless latest_allowable_version.backwards_compatible_with?(latest_types_package_version)

            return false unless version_class.correct?(types_package.version)

            current_types_package_version = version_class.new(types_package.version)

            return false unless current_types_package_version < latest_types_package_version

            true
          end

          def original_package_update_available?
            return false if original_package.nil?

            return false unless version_class.correct?(original_package.version)

            original_package_version = version_class.new(original_package.version)

            latest_version = latest_version_finder(original_package).latest_version_from_registry

            # If the latest version is within the scope of the current requirements,
            # latest_version will be nil. In such cases, there is no update available.
            return false if latest_version.nil?

            original_package_version < latest_version
          end

          def updated_types_dependencies
            [{
              dependency: types_package,
              version: latest_types_package_version,
              previous_version: resolve_latest_previous_version(
                types_package, latest_types_package_version
              )
            }]
          end

          def peer_dependency_errors
            return @peer_dependency_errors if @peer_dependency_errors_checked

            @peer_dependency_errors_checked = true

            @peer_dependency_errors =
              fetch_peer_dependency_errors(version: latest_allowable_version)
          end

          def old_peer_dependency_errors
            return @old_peer_dependency_errors if @old_peer_dependency_errors_checked

            @old_peer_dependency_errors_checked = true

            version = version_for_dependency(dependency)

            @old_peer_dependency_errors =
              fetch_peer_dependency_errors(version: version)
          end

          def fetch_peer_dependency_errors(version:)
            # TODO: Add all of the error handling that the FileUpdater does
            # here (since problematic repos will be resolved here before they're
            # seen by the FileUpdater)
            base_dir = dependency_files.first.directory
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

          def unmet_peer_dependencies
            peer_dependency_errors
              .map { |captures| error_details_from_captures(captures) }
          end

          def old_unmet_peer_dependencies
            old_peer_dependency_errors
              .map { |captures| error_details_from_captures(captures) }
          end

          def error_details_from_captures(captures)
            return {} unless captures.is_a?(Hash)

            required_dep_captures  = captures.fetch("required_dep")
            requiring_dep_captures = captures.fetch("requiring_dep")
            return {} unless required_dep_captures && requiring_dep_captures

            {
              requirement_name: required_dep_captures.sub(/@[^@]+$/, ""),
              requirement_version: required_dep_captures.split("@").last.delete('"'),
              requiring_dep_name: requiring_dep_captures.sub(/@[^@]+$/, "")
            }
          end

          def relevant_unmet_peer_dependencies
            relevant_unmet_peer_dependencies =
              unmet_peer_dependencies.select do |dep|
                dep[:requirement_name] == dependency.name ||
                  dep[:requiring_dep_name] == dependency.name
              end

            unless dependency_group.nil?
              # Ignore unmet peer dependencies that are in the dependency group because
              # the update is also updating those dependencies.
              relevant_unmet_peer_dependencies.reject! do |dep|
                dependency_group.dependencies.any? do |group_dep|
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
          def satisfying_versions
            latest_version_finder(dependency)
              .possible_versions_with_details
              .select do |version, details|
                next false unless satisfies_peer_reqs_on_dep?(version)
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
              end
              .map(&:first)
          end

          # rubocop:enable Metrics/PerceivedComplexity

          def satisfies_peer_reqs_on_dep?(version)
            newly_broken_peer_reqs_on_dep.all? do |peer_req|
              req = peer_req.fetch(:requirement_version)

              # Git requirements can't be satisfied by a version
              next false if req.include?("/")

              reqs = requirement_class.requirements_array(req)
              reqs.any? { |r| r.satisfied_by?(version) }
            rescue Gem::Requirement::BadRequirementError
              false
            end
          end

          def latest_version_of_dep_with_satisfied_peer_reqs(dep)
            latest_version_finder(dep)
              .possible_versions_with_details
              .find do |version, details|
                next false unless version > version_for_dependency(dep)
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
              &.first
          end

          def git_dependency?(dep)
            # ignored_version/raise_on_ignored are irrelevant.
            GitCommitChecker
              .new(dependency: dep, credentials: credentials)
              .git_dependency?
          end

          def newly_broken_peer_reqs_on_dep
            relevant_unmet_peer_dependencies
              .select { |dep| dep[:requirement_name] == dependency.name }
          end

          def newly_broken_peer_reqs_from_dep
            relevant_unmet_peer_dependencies
              .select { |dep| dep[:requiring_dep_name] == dependency.name }
          end

          def lockfiles_for_path(lockfiles:, path:)
            lockfiles.select do |lockfile|
              File.dirname(lockfile.name) == File.dirname(path)
            end
          end

          def run_checker(path:, version:)
            bun_lockfiles = lockfiles_for_path(lockfiles: dependency_files_builder.bun_locks, path: path)
            return run_bun_checker(path: path, version: version) if bun_lockfiles.any?

            root_bun_lock = dependency_files_builder.root_bun_lock
            run_bun_checker(path: path, version: version) if root_bun_lock
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

          def version_install_arg(version:)
            git_source = dependency.requirements.find { |req| req[:source] && req[:source][:type] == "git" }

            if git_source
              "#{dependency.name}@#{git_source[:source][:url]}##{version}"
            else
              "#{dependency.name}@#{version}"
            end
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
          def top_level_dependencies
            @top_level_dependencies ||= Bun::FileParser.new(
              dependency_files: dependency_files,
              source: nil,
              credentials: credentials
            ).parse.select(&:top_level?)
          end

          def paths_requiring_update_check
            @paths_requiring_update_check ||=
              Dependabot::Javascript::Shared::DependencyFilesFilterer.new(
                dependency_files: dependency_files,
                updated_dependencies: [dependency],
                lockfile_parser_class: FileParser::LockfileParser
              ).paths_requiring_update_check
          end

          def dependency_files_builder
            @dependency_files_builder ||=
              DependencyFilesBuilder.new(
                dependency: dependency,
                dependency_files: dependency_files,
                credentials: credentials
              )
          end

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

          def version_class
            dependency.version_class
          end

          def requirement_class
            dependency.requirement_class
          end

          def version_regex
            Dependabot::Javascript::Shared::Version::VERSION_PATTERN
          end
        end
      end
    end
  end
end
