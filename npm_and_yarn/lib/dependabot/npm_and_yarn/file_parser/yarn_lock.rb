# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/npm_and_yarn/native_helpers"

module Dependabot
  module NpmAndYarn
    class FileParser
      class YarnLock
        def initialize(dependency_file)
          @dependency_file = dependency_file
        end

        def parsed
          @parsed ||= SharedHelpers.in_a_temporary_directory do
            File.write("yarn.lock", @dependency_file.content)

            SharedHelpers.run_helper_subprocess(
              command: NativeHelpers.helper_path,
              function: "yarn:parseLockfile",
              args: [Dir.pwd]
            )
          rescue SharedHelpers::HelperSubprocessFailed
            raise Dependabot::DependencyFileNotParseable, @dependency_file.path
          end
        end

        def dependencies
          dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new

          parsed.each do |reqs, details|
            reqs.split(", ").each do |req|
              version = Version.semver_for(details["version"])
              next unless version
              next if alias_package?(req)
              next if workspace_package?(req)
              next if req == "__metadata"

              dependency_set << Dependency.new(
                name: req.split(/(?<=\w)\@/).first,
                version: version,
                package_manager: "npm_and_yarn",
                requirements: []
              )
            end
          end

          dependency_set
        end

        def details(dependency_name, requirement, _manifest_name)
          details_candidates =
            parsed.
            select { |k, _| k.split(/(?<=\w)\@/)[0] == dependency_name }

          # If there's only one entry for this dependency, use it, even if
          # the requirement in the lockfile doesn't match
          if details_candidates.one?
            details_candidates.first.last
          else
            details_candidates.find do |k, _|
              k.scan(/(?<=\w)\@(?:npm:)?([^\s,]+)/).flatten.include?(requirement)
            end&.last
          end
        end

        private

        def alias_package?(requirement)
          requirement.match?(/@npm:(.+@(?!npm))/)
        end

        def workspace_package?(requirement)
          requirement.include?("@workspace:")
        end
      end
    end
  end
end
