# frozen_string_literal: true

require "dependabot/errors"

module Dependabot
  module NpmAndYarn
    class FileParser
      class PnpmLock
        def initialize(dependency_file)
          @dependency_file = dependency_file
        end

        def parsed
          @parsed ||= SharedHelpers.in_a_temporary_directory do
            File.write("pnpm-lock.yaml", @dependency_file.content)

            SharedHelpers.run_helper_subprocess(
              command: NativeHelpers.helper_path,
              function: "pnpm:parseLockfile",
              args: [Dir.pwd]
            )
          rescue SharedHelpers::HelperSubprocessFailed
            raise Dependabot::DependencyFileNotParseable, @dependency_file.path
          end
        end

        def dependencies
          dependency_set = Dependabot::NpmAndYarn::FileParser::DependencySet.new

          parsed.each do |details|
            next if details["aliased"]

            name = details["name"]
            version = details["version"]

            dependency_args = {
              name: name,
              version: version,
              package_manager: "npm_and_yarn",
              requirements: []
            }

            if details["dev"]
              dependency_args[:subdependency_metadata] =
                [{ production: !details["dev"] }]
            end

            dependency_set << Dependency.new(**dependency_args)
          end

          dependency_set
        end

        def details(dependency_name, requirement, _manifest_name)
          details_candidates = parsed.select { |info| info["name"] == dependency_name }

          # If there's only one entry for this dependency, use it, even if
          # the requirement in the lockfile doesn't match
          if details_candidates.one?
            details_candidates.first
          else
            details_candidates.find { |info| info["specifiers"]&.include?(requirement) }
          end
        end
      end
    end
  end
end
