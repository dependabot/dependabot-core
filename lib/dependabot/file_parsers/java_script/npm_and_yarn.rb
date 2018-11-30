# frozen_string_literal: true

# See https://docs.npmjs.com/files/package.json for package.json format docs.

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/errors"

# rubocop:disable Metrics/ClassLength
module Dependabot
  module FileParsers
    module JavaScript
      class NpmAndYarn < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/base/dependency_set"

        DEPENDENCY_TYPES =
          %w(dependencies devDependencies optionalDependencies).freeze
        CENTRAL_REGISTRIES = %w(
          https://registry.npmjs.org
          http://registry.npmjs.org
          https://registry.yarnpkg.com
        ).freeze
        GIT_URL_REGEX = %r{
          (?:^|^git.*?|^github:|^bitbucket:|^gitlab:|github\.com/)
          (?<username>[a-z0-9-]+)/
          (?<repo>[a-z0-9_.-]+)
          (
            (?:\#semver:(?<semver>.+))|
            (?:\#(?<ref>.+))
          )?$
        }ix.freeze

        def parse
          dependency_set = DependencySet.new
          dependency_set += manifest_dependencies
          dependency_set += yarn_lock_dependencies if yarn_locks.any?
          dependency_set += package_lock_dependencies if package_locks.any?
          dependency_set += shrinkwrap_dependencies if shrinkwraps.any?
          dependencies = dependency_set.dependencies

          # TODO: Currently, Dependabot can't handle dependencies that have both
          # a git source *and* a non-git source. Fix that!
          dependencies.reject do |dep|
            dep.requirements.any? { |r| r.dig(:source, :type) == "git" } &&
              dep.requirements.any? { |r| r.dig(:source, :type) != "git" }
          end
        end

        private

        def manifest_dependencies
          dependency_set = DependencySet.new

          package_files.each do |file|
            # TODO: Currently, Dependabot can't handle flat dependency files
            # (and will error at the FileUpdater stage, because the
            # UpdateChecker doesn't take account of flat resolution).
            next if JSON.parse(file.content)["flat"]

            DEPENDENCY_TYPES.each do |type|
              deps = JSON.parse(file.content)[type] || {}
              deps.each do |name, requirement|
                requirement = "*" if requirement == ""
                dep = build_dependency(
                  file: file, type: type, name: name, requirement: requirement
                )
                dependency_set << dep if dep
              end
            end
          end

          dependency_set
        end

        def yarn_lock_dependencies
          dependency_set = DependencySet.new

          yarn_locks.each do |yarn_lock|
            parse_yarn_lock(yarn_lock).each do |req, details|
              next unless details["version"] && details["version"] != ""

              # Note: The DependencySet will de-dupe our dependencies, so they
              # end up unique by name. That's not a perfect representation of
              # the nested nature of JS resolution, but it makes everything work
              # comparably to other flat-resolution strategies
              dependency_set << Dependency.new(
                name: req.split(/(?<=\w)\@/).first,
                version: details["version"],
                package_manager: "npm_and_yarn",
                requirements: []
              )
            end
          end

          dependency_set
        end

        def package_lock_dependencies
          dependency_set = DependencySet.new

          # Note: The DependencySet will de-dupe our dependencies, so they
          # end up unique by name. That's not a perfect representation of
          # the nested nature of JS resolution, but it makes everything work
          # comparably to other flat-resolution strategies
          package_locks.each do |package_lock|
            parsed_lockfile = parse_package_lock(package_lock)
            deps = recursively_fetch_npm_lock_dependencies(parsed_lockfile)
            dependency_set += deps
          end

          dependency_set
        end

        def shrinkwrap_dependencies
          dependency_set = DependencySet.new

          # Note: The DependencySet will de-dupe our dependencies, so they
          # end up unique by name. That's not a perfect representation of
          # the nested nature of JS resolution, but it makes everything work
          # comparably to other flat-resolution strategies
          shrinkwraps.each do |shrinkwrap|
            parsed_lockfile = parse_shrinkwrap(shrinkwrap)
            deps = recursively_fetch_npm_lock_dependencies(parsed_lockfile)
            dependency_set += deps
          end

          dependency_set
        end

        def recursively_fetch_npm_lock_dependencies(object_with_dependencies)
          dependency_set = DependencySet.new

          object_with_dependencies.
            fetch("dependencies", {}).each do |name, details|
              next unless details["version"] && details["version"] != ""

              dependency_set << Dependency.new(
                name: name,
                version: details["version"],
                package_manager: "npm_and_yarn",
                requirements: []
              )

              dependency_set += recursively_fetch_npm_lock_dependencies(details)
            end

          dependency_set
        end

        def build_dependency(file:, type:, name:, requirement:)
          return if lockfile_details(name, requirement) &&
                    !version_for(name, requirement)
          return if ignore_requirement?(requirement)
          return if workspace_package_names.include?(name)

          Dependency.new(
            name: name,
            version: version_for(name, requirement),
            package_manager: "npm_and_yarn",
            requirements: [{
              requirement: requirement_for(requirement),
              file: file.name,
              groups: [type],
              source: source_for(name, requirement)
            }]
          )
        end

        def check_required_files
          raise "No package.json!" unless get_original_file("package.json")
        end

        def ignore_requirement?(requirement)
          return true if local_path?(requirement)
          return true if non_git_url?(requirement)

          # TODO: Handle aliased packages
          alias_package?(requirement)
        end

        def local_path?(requirement)
          requirement.start_with?("link:", "file:", "/", "./", "../", "~/")
        end

        def alias_package?(requirement)
          requirement.start_with?("npm:")
        end

        def non_git_url?(requirement)
          requirement.include?("://") && !git_url?(requirement)
        end

        def git_url?(requirement)
          requirement.match?(GIT_URL_REGEX)
        end

        def workspace_package_names
          @workspace_package_names ||=
            package_files.map { |f| JSON.parse(f.content)["name"] }.compact
        end

        # rubocop:disable Metrics/CyclomaticComplexity
        # rubocop:disable Metrics/PerceivedComplexity
        def version_for(name, requirement)
          lock_version = lockfile_details(name, requirement)&.
                         fetch("version", nil)
          lock_res     = lockfile_details(name, requirement)&.
                         fetch("resolved", nil)

          if git_url?(requirement)
            return lock_version.split("#").last if lock_version&.include?("#")
            return lock_res.split("#").last if lock_res&.include?("#")

            if lock_res && lock_res.split("/").last.match?(/^[0-9a-f]{40}$/)
              return lock_res.split("/").last
            end

            return nil
          end

          return unless lock_version
          return if lock_version.include?("://")
          return if lock_version.include?("file:")
          return if lock_version.include?("link:")
          return if lock_version.include?("#")

          lock_version
        end
        # rubocop:enable Metrics/CyclomaticComplexity
        # rubocop:enable Metrics/PerceivedComplexity

        def source_for(name, requirement)
          return git_source_for(requirement) if git_url?(requirement)

          resolved_url = lockfile_details(name, requirement)&.
                         fetch("resolved", nil)

          return unless resolved_url
          return if CENTRAL_REGISTRIES.any? { |u| resolved_url.start_with?(u) }
          return if resolved_url.include?("github")

          private_registry_source_for(resolved_url, name)
        end

        def requirement_for(requirement)
          return requirement unless git_url?(requirement)

          details = requirement.match(GIT_URL_REGEX).named_captures
          details["semver"]
        end

        def git_source_for(requirement)
          details = requirement.match(GIT_URL_REGEX).named_captures
          {
            type: "git",
            url: "https://github.com/#{details['username']}/#{details['repo']}",
            branch: nil,
            ref: details["ref"] || "master"
          }
        end

        def private_registry_source_for(resolved_url, name)
          url =
            if resolved_url.include?("/~/")
              # Gemfury format
              resolved_url.split("/~/").first
            elsif resolved_url.include?("/#{name}/-/#{name}")
              # Sonatype Nexus / Artifactory JFrog format
              resolved_url.split("/#{name}/-/#{name}").first
            elsif (cred_url = credential_url(resolved_url)) then cred_url
            else resolved_url.split("/")[0..2].join("/")
            end

          { type: "private_registry", url: url }
        end

        def credential_url(resolved_url)
          registries = credentials.
                       select { |cred| cred["type"] == "npm_registry" }

          registries.each do |details|
            reg = details["registry"]
            next unless resolved_url.include?(reg)

            return resolved_url.gsub(/#{Regexp.quote(reg)}.*/, "") + reg
          end

          false
        end

        def lockfile_details(name, requirement)
          [*package_locks, *shrinkwraps].each do |package_lock|
            parsed_package_lock_json = parse_package_lock(package_lock)
            next unless parsed_package_lock_json.dig("dependencies", name)

            return parsed_package_lock_json.dig("dependencies", name)
          end

          req = requirement
          yarn_locks.each do |yarn_lock|
            parsed_yarn_lock = parse_yarn_lock(yarn_lock)

            details_candidates =
              parsed_yarn_lock.
              select { |k, _| k.split(/(?<=\w)\@/).first == name }

            # If there's only one entry for this dependency, use it, even if
            # the requirement in the lockfile doesn't match
            details = details_candidates.first.last if details_candidates.one?

            details ||=
              details_candidates.
              find { |k, _| k.split(/(?<=\w)\@/)[1..-1].join("@") == req }&.
              last

            return details if details
          end

          nil
        end

        def parse_package_lock(package_lock)
          JSON.parse(package_lock.content)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, package_lock.path
        end

        def parse_shrinkwrap(shrinkwrap)
          JSON.parse(shrinkwrap.content)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, shrinkwrap.path
        end

        def parse_yarn_lock(yarn_lock)
          @parsed_yarn_lock ||= {}
          @parsed_yarn_lock[yarn_lock.name] ||=
            SharedHelpers.in_a_temporary_directory do
              File.write("yarn.lock", yarn_lock.content)

              SharedHelpers.run_helper_subprocess(
                command: "node #{yarn_helper_path}",
                function: "parseLockfile",
                args: [Dir.pwd]
              )
            rescue SharedHelpers::HelperSubprocessFailed
              raise Dependabot::DependencyFileNotParseable, yarn_lock.path
            end
        end

        def yarn_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/yarn/bin/run.js")
        end

        def package_files
          sub_packages =
            dependency_files.
            select { |f| f.name.end_with?("package.json") }.
            reject { |f| f.name == "package.json" }.
            reject { |f| f.type == "path_dependency" }

          [
            dependency_files.find { |f| f.name == "package.json" },
            *sub_packages
          ].compact
        end

        def lockfile?
          package_locks.any? || yarn_locks.any?
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
      end
    end
  end
end
# rubocop:enable Metrics/ClassLength
