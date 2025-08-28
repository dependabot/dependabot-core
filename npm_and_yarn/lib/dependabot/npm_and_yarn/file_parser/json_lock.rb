# typed: strict
# frozen_string_literal: true

require "json"
require "dependabot/errors"
require "dependabot/npm_and_yarn/helpers"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class FileParser < Dependabot::FileParsers::Base
      class JsonLock
        extend T::Sig

        sig { params(dependency_file: DependencyFile).void }
        def initialize(dependency_file)
          @dependency_file = dependency_file
          # Set this file to priority 1 to indicate it should override manifests for purposes of a graph
          dependency_file.priority = 1
          @direct_dependencies = T.let(fetch_direct_dependencies, T::Array[String])
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed
          json_obj = JSON.parse(T.must(@dependency_file.content))
          @parsed ||= T.let(json_obj, T.untyped)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, @dependency_file.path
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependencies
          recursively_fetch_dependencies(parsed)
        end

        sig do
          params(dependency_name: String, _requirement: T.untyped, manifest_name: String)
            .returns(T.nilable(T::Hash[String, T.untyped]))
        end
        def details(dependency_name, _requirement, manifest_name)
          if Helpers.parse_npm8?(@dependency_file)
            # NOTE: npm 8 sometimes doesn't install workspace dependencies in the
            # workspace folder so we need to fallback to checking top-level
            nested_details = parsed.dig("packages", node_modules_path(manifest_name, dependency_name))
            details = nested_details || parsed.dig("packages", "node_modules/#{dependency_name}")
            details&.slice("version", "resolved", "integrity", "dev")
          else
            parsed.dig("dependencies", dependency_name)
          end
        end

        private

        # Only V3 lockfiles contain information on the package itself, so we use `npm ls` to generate
        # a graph we can pluck the direct dependency list from at parse-time for this lockfile.
        sig { returns(T::Array[String]) }
        def fetch_direct_dependencies
          # TODO(brrygrdn): Implement a 'verbose' flag that runs this extra step?
          #
          # For now, don't run this extra native command if we aren't using the submission experiment
          return [] unless Dependabot::Experiments.enabled?(:enable_dependency_submission_poc)

          SharedHelpers.in_a_temporary_repo_directory do |_|
            write_temporary_dependency_files

            npm_ls_json = Helpers.run_npm_command("ls --all --package-lock-only --json")

            JSON.parse(npm_ls_json).fetch("dependencies", {}).keys
          end
        end

        sig { void }
        def write_temporary_dependency_files
          path = @dependency_file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, @dependency_file.content)
        end

        sig do
          params(object_with_dependencies: T::Hash[String, T.untyped])
            .returns(Dependabot::FileParsers::Base::DependencySet)
        end
        def recursively_fetch_dependencies(object_with_dependencies) # rubocop:disable Metrics/AbcSize
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          dependencies = object_with_dependencies["dependencies"]
          dependencies ||= object_with_dependencies.fetch("packages", {})

          dependencies.each do |name, details|
            next if name.empty? # v3 lockfiles include an empty key holding info of the current package

            version = Version.semver_for(details["version"])
            next unless version

            package_name = name.split("node_modules/").last
            version = version.to_s

            origin_file = Pathname.new(@dependency_file.directory).join(@dependency_file.name).to_s

            dependency_args = {
              name: package_name,
              version: version,
              package_manager: "npm_and_yarn",
              requirements: [],
              direct_relationship: @direct_dependencies.include?(package_name),
              metadata: {
                depends_on: details&.fetch("dependencies", {})&.keys || []
              },
              origin_files: [origin_file]
            }

            if details["bundled"]
              dependency_args[:subdependency_metadata] =
                [{ npm_bundled: details["bundled"] }]
            end

            if details["dev"]
              dependency_args[:subdependency_metadata] =
                [{ production: !details["dev"] }]
            end

            dependency_set << Dependency.new(**dependency_args)
            dependency_set += recursively_fetch_dependencies(details)
          end

          @dependency_file.dependencies = dependency_set.dependencies.to_set
          dependency_set
        end

        sig { params(manifest_name: String, dependency_name: String).returns(String) }
        def node_modules_path(manifest_name, dependency_name)
          return "node_modules/#{dependency_name}" if manifest_name == "package.json"

          workspace_path = manifest_name.gsub("/package.json", "")
          File.join(workspace_path, "node_modules", dependency_name)
        end
      end
    end
  end
end
