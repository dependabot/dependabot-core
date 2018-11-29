# frozen_string_literal: true

require "dependabot/git_commit_checker"
require "dependabot/update_checkers/java_script/npm_and_yarn"
require "dependabot/file_parsers/java_script/npm_and_yarn"
require "dependabot/utils/java_script/version"
require "dependabot/utils/java_script/requirement"
require "dependabot/shared_helpers"
require "dependabot/errors"

file_updater_path = "dependabot/file_updaters/java_script/npm_and_yarn"
require "#{file_updater_path}/npmrc_builder"
require "#{file_updater_path}/package_json_preparer"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module UpdateCheckers
    module JavaScript
      class NpmAndYarn
        class VersionResolver
          require_relative "latest_version_finder"

          # Error message from yarn add:
          # " > @reach/router@1.2.1" has incorrect \
          # peer dependency "react@15.x || 16.x || 16.4.0-alpha.0911da3"
          # " > react-burger-menu@1.9.9" has unmet \
          # peer dependency "react@>=0.14.0 <16.0.0".
          YARN_PEER_DEP_ERROR_REGEX =
            /
              "\s>\s(?<requiring_dep>[^"]+)"\s
              has\s(incorrect|unmet)\speer\sdependency\s
              "(?<required_dep>[^"]+)"
            /x.freeze

          # Error message from npm install:
          # react-dom@15.2.0 requires a peer of react@^15.2.0 \
          # but none is installed. You must install peer dependencies yourself.
          NPM_PEER_DEP_ERROR_REGEX =
            /
              (?<requiring_dep>[^\s]+)\s
              requires\sa\speer\sof\s
              (?<required_dep>.+?)\sbut\snone\sis\sinstalled.
            /x.freeze

          def initialize(dependency:, credentials:, dependency_files:,
                         latest_allowable_version:, latest_version_finder:)
            @dependency               = dependency
            @credentials              = credentials
            @dependency_files         = dependency_files
            @latest_allowable_version = latest_allowable_version

            @latest_version_finder = {}
            @latest_version_finder[dependency] = latest_version_finder
          end

          def latest_resolvable_version
            return latest_allowable_version if git_dependency?(dependency)

            unless relevant_unmet_peer_dependencies.any?
              return latest_allowable_version
            end

            satisfying_versions.first
          end

          def latest_version_resolvable_with_full_unlock?
            return false if dependency_updates_from_full_unlock.nil?

            true
          end

          def dependency_updates_from_full_unlock
            return if git_dependency?(dependency)
            return if newly_broken_peer_reqs_from_dep.any?

            updates =
              [{ dependency: dependency, version: latest_allowable_version }]
            newly_broken_peer_reqs_on_dep.each do |peer_req|
              dep_name = peer_req.fetch(:requiring_dep_name)
              dep = top_level_dependencies.find { |d| d.name == dep_name }

              # Can't handle reqs from sub-deps or git source deps (yet)
              return nil if dep.nil?
              return nil if git_dependency?(dep)

              updated_version =
                latest_version_of_dep_with_satisfied_peer_reqs(dep)
              return nil unless updated_version

              updates << { dependency: dep, version: updated_version }
            end

            updates
          end

          private

          attr_reader :dependency, :credentials, :dependency_files,
                      :latest_allowable_version

          def latest_version_finder(dep)
            @latest_version_finder[dep] ||=
              LatestVersionFinder.new(
                dependency: dep,
                credentials: credentials,
                dependency_files: dependency_files,
                ignored_versions: []
              )
          end

          def peer_dependency_errors
            return @peer_dependency_errors if @peer_dependency_errors_checked

            @peer_dependency_errors_checked = true

            @peer_dependency_errors =
              fetch_peer_dependency_errors(version: latest_allowable_version)
          end

          def old_peer_dependency_errors
            if @old_peer_dependency_errors_checked
              return @old_peer_dependency_errors
            end

            @old_peer_dependency_errors_checked = true

            @old_peer_dependency_errors =
              fetch_peer_dependency_errors(version: dependency.version)
          end

          def fetch_peer_dependency_errors(version:)
            # TODO: Add all of the error handling that the FileUpdater does
            # here (since problematic repos will be resolved here before they're
            # seen by the FileUpdater)
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              package_files.flat_map do |file|
                path = Pathname.new(file.name).dirname
                run_checker(path: path, version: version)
              rescue SharedHelpers::HelperSubprocessFailed => error
                errors = []
                if error.message.match?(NPM_PEER_DEP_ERROR_REGEX)
                  error.message.scan(NPM_PEER_DEP_ERROR_REGEX) do
                    errors << Regexp.last_match.named_captures
                  end
                elsif error.message.match?(YARN_PEER_DEP_ERROR_REGEX)
                  error.message.scan(YARN_PEER_DEP_ERROR_REGEX) do
                    errors << Regexp.last_match.named_captures
                  end
                else raise
                end
                errors
              end.compact
            end
          rescue SharedHelpers::HelperSubprocessFailed
            # Fall back to allowing the version through. Whatever error
            # occurred should be properly handled by the FileUpdater. We
            # can slowly migrate error handling to this class over time.
            []
          end

          def unmet_peer_dependencies
            peer_dependency_errors.
              map { |captures| error_details_from_captures(captures) }
          end

          def old_unmet_peer_dependencies
            old_peer_dependency_errors.
              map { |captures| error_details_from_captures(captures) }
          end

          def error_details_from_captures(captures)
            {
              requirement_name:
                captures.fetch("required_dep").sub(/@[^@]+$/, ""),
              requirement_version:
                captures.fetch("required_dep").split("@").last,
              requiring_dep_name:
                captures.fetch("requiring_dep").sub(/@[^@]+$/, "")
            }
          end

          def relevant_unmet_peer_dependencies
            relevant_unmet_peer_dependencies =
              unmet_peer_dependencies.select do |dep|
                dep[:requirement_name] == dependency.name ||
                  dep[:requiring_dep_name] == dependency.name
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

          def satisfying_versions
            latest_version_finder(dependency).
              possible_versions_with_details.
              select do |version, details|
                next false unless satisfies_peer_reqs_on_dep?(version)
                next true unless details["peerDependencies"]

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
              end.
              map(&:first)
          end

          def satisfies_peer_reqs_on_dep?(version)
            newly_broken_peer_reqs_on_dep.all? do |peer_req|
              req = peer_req.fetch(:requirement_version)

              # Git requirements can't be satisfied by a version
              next false if req.include?("/")

              reqs = requirement_class.requirements_array(req)
              reqs.any? { |r| r.satisfied_by?(version) }
            end
          end

          def latest_version_of_dep_with_satisfied_peer_reqs(dep)
            latest_version_finder(dep).
              possible_versions_with_details.
              find do |version, details|
                next false unless version > version_class.new(dep.version)
                next true unless details["peerDependencies"]

                details["peerDependencies"].all? do |peer_dep_name, req|
                  # Can't handle multiple peer dependencies
                  next false unless peer_dep_name == dependency.name
                  next git_dependency?(dependency) if req.include?("/")

                  reqs = requirement_class.requirements_array(req)

                  reqs.any? { |r| r.satisfied_by?(latest_allowable_version) }
                end
              end&.
              first
          end

          def git_dependency?(dep)
            GitCommitChecker.
              new(dependency: dep, credentials: credentials).
              git_dependency?
          end

          def newly_broken_peer_reqs_on_dep
            relevant_unmet_peer_dependencies.
              select { |dep| dep[:requirement_name] == dependency.name }
          end

          def newly_broken_peer_reqs_from_dep
            relevant_unmet_peer_dependencies.
              select { |dep| dep[:requiring_dep_name] == dependency.name }
          end

          def run_checker(path:, version:)
            if [*package_locks, *shrinkwraps].any?
              run_npm_checker(path: path, version: version)
            end

            run_yarn_checker(path: path, version: version) if yarn_locks.any?
            run_yarn_checker(path: path, version: version) if lockfiles.none?
          end

          def run_yarn_checker(path:, version:)
            SharedHelpers.with_git_configured(credentials: credentials) do
              Dir.chdir(path) do
                SharedHelpers.run_helper_subprocess(
                  command: "node #{yarn_helper_path}",
                  function: "checkPeerDependencies",
                  args: [
                    Dir.pwd,
                    dependency.name,
                    version,
                    requirements_for_path(dependency.requirements, path)
                  ]
                )
              end
            end
          end

          def run_npm_checker(path:, version:)
            SharedHelpers.with_git_configured(credentials: credentials) do
              Dir.chdir(path) do
                SharedHelpers.run_helper_subprocess(
                  command: "node #{npm_helper_path}",
                  function: "checkPeerDependencies",
                  args: [
                    Dir.pwd,
                    dependency.name,
                    version,
                    requirements_for_path(dependency.requirements, path),
                    top_level_dependencies.map(&:to_h)
                  ]
                )
              end
            end
          end

          def requirements_for_path(requirements, path)
            return requirements if path.to_s == "."

            requirements.map do |r|
              next unless r[:file].start_with?("#{path}/")

              r.merge(file: r[:file].gsub(/^#{Regexp.quote("#{path}/")}/, ""))
            end.compact
          end

          def write_temporary_dependency_files
            write_lock_files

            File.write(".npmrc", npmrc_content)

            package_files.each do |file|
              path = file.name
              FileUtils.mkdir_p(Pathname.new(path).dirname)
              File.write(file.name, prepared_package_json_content(file))
            end
          end

          def write_lock_files
            yarn_locks.each do |f|
              FileUtils.mkdir_p(Pathname.new(f.name).dirname)
              File.write(f.name, prepared_yarn_lockfile_content(f.content))
            end

            package_locks.each do |f|
              FileUtils.mkdir_p(Pathname.new(f.name).dirname)
              File.write(f.name, f.content)
            end

            shrinkwraps.each do |f|
              FileUtils.mkdir_p(Pathname.new(f.name).dirname)
              File.write(f.name, f.content)
            end
          end

          def prepared_yarn_lockfile_content(content)
            content.gsub(/^#{Regexp.quote(dependency.name)}\@.*?\n\n/m, "")
          end

          def prepared_package_json_content(file)
            FileUpdaters::JavaScript::NpmAndYarn::PackageJsonPreparer.new(
              package_json_content: file.content
            ).prepared_content
          end

          def npmrc_content
            FileUpdaters::JavaScript::NpmAndYarn::NpmrcBuilder.new(
              credentials: credentials,
              dependency_files: dependency_files
            ).npmrc_content
          end

          # Top level dependecies are required in the peer dep checker
          # to fetch the manifests for all top level deps which may contain
          # "peerDependency" requirements
          def top_level_dependencies
            @top_level_dependencies ||= FileParsers::JavaScript::NpmAndYarn.new(
              dependency_files: dependency_files,
              source: nil,
              credentials: credentials
            ).parse.select(&:top_level?)
          end

          def lockfiles
            [*yarn_locks, *package_locks, *shrinkwraps]
          end

          def package_locks
            @package_locks ||=
              dependency_files.
              select { |f| f.name.end_with?("package-lock.json") }
          end

          def yarn_locks
            @yarn_locks ||=
              dependency_files.
              select { |f| f.name.end_with?("yarn.lock") }
          end

          def shrinkwraps
            @shrinkwraps ||=
              dependency_files.
              select { |f| f.name.end_with?("npm-shrinkwrap.json") }
          end

          def package_files
            @package_files ||=
              dependency_files.
              select { |f| f.name.end_with?("package.json") }
          end

          def yarn_helper_path
            project_root = File.join(File.dirname(__FILE__), "../../../../..")
            File.join(project_root, "helpers/yarn/bin/run.js")
          end

          def npm_helper_path
            project_root = File.join(File.dirname(__FILE__), "../../../../..")
            File.join(project_root, "helpers/npm/bin/run.js")
          end

          def version_for_dependency(dep)
            if dep.version && version_class.correct?(dep.version)
              return version_class.new(dep.version)
            end

            dep.requirements.map { |r| r[:requirement] }.compact.
              reject { |req_string| req_string.start_with?("<") }.
              select { |req_string| req_string.match?(version_regex) }.
              map { |req_string| req_string.match(version_regex) }.
              select { |version| version_class.correct?(version.to_s) }.
              map { |version| version_class.new(version.to_s) }.
              max
          end

          def version_class
            Utils::JavaScript::Version
          end

          def requirement_class
            Utils::JavaScript::Requirement
          end

          def version_regex
            version_class::VERSION_PATTERN
          end
        end
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
