# typed: true
# frozen_string_literal: true

require "dependabot/errors"

module Dependabot
  module NpmAndYarn
    class FileParser < Dependabot::FileParsers::Base
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
          if Dependabot::Experiments.enabled?(:enable_fix_for_pnpm_no_change_error)
            return dependencies_with_prioritization
          end

          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

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

        def dependencies_with_prioritization
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          # Separate dependencies into two categories: with specifiers and without specifiers.
          dependencies_with_specifiers = [] # Main dependencies with specifiers.
          dependencies_without_specifiers = [] # Subdependencies without specifiers.

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

            # Add metadata for subdependencies if marked as a dev dependency.
            dependency_args[:subdependency_metadata] = [{ production: !details["dev"] }] if details["dev"]

            specifiers = details["specifiers"]
            if specifiers&.any?
              dependencies_with_specifiers << dependency_args
            else
              dependencies_without_specifiers << dependency_args
            end
          end

          # Add prioritized dependencies to the dependency set.
          dependencies_with_specifiers.each do |dependency_args|
            dependency_set << Dependency.new(**dependency_args)
          end

          dependencies_without_specifiers.each do |dependency_args|
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
