# typed: strict
# frozen_string_literal: true

require "dependabot/shared_helpers"
require "dependabot/errors"
require "dependabot/npm_and_yarn/native_helpers"
require "sorbet-runtime"

module Dependabot
  module NpmAndYarn
    class FileParser < Dependabot::FileParsers::Base
      class YarnLock
        extend T::Sig

        sig { params(dependency_file: Dependabot::DependencyFile, dealias_packages: T::Boolean).void }
        def initialize(dependency_file, dealias_packages: false)
          @dependency_file = dependency_file
          @dealias_packages = dealias_packages
        end

        sig { returns(T::Hash[String, T::Hash[String, T.untyped]]) }
        def parsed
          @parsed ||= T.let(
            T.cast(
              SharedHelpers.in_a_temporary_directory do
                File.write("yarn.lock", @dependency_file.content)

                SharedHelpers.run_helper_subprocess(
                  command: NativeHelpers.helper_path,
                  function: "yarn:parseLockfile",
                  args: [Dir.pwd]
                )
              rescue SharedHelpers::HelperSubprocessFailed => e
                raise Dependabot::OutOfDisk, e.message if e.message.end_with?("No space left on device")
                raise Dependabot::OutOfDisk, e.message if e.message.end_with?("Out of diskspace")
                raise Dependabot::OutOfMemory, e.message if e.message.end_with?("MemoryError")

                raise Dependabot::DependencyFileNotParseable, @dependency_file.path
              end,
              T::Hash[String, T::Hash[String, T.untyped]]
            ),
            T.nilable(T::Hash[String, T::Hash[String, T.untyped]])
          )
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependencies
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          parsed.each do |reqs, details|
            reqs.split(", ").each do |req|
              version = Version.semver_for(details["version"])
              next unless version
              next if workspace_package?(req)
              next if req == "__metadata"

              if alias_package?(req)
                # Skip unless we are dealiasing packages
                next unless dealias_packages?

                real_name = extract_real_name_from_yarn_alias(req)
                next unless real_name

                dependency_set << Dependency.new(
                  name: real_name,
                  version: version.to_s,
                  package_manager: "npm_and_yarn",
                  requirements: []
                )
              else
                dependency_set << Dependency.new(
                  name: T.must(req.split(/(?<=\w)\@/).first),
                  version: version.to_s,
                  package_manager: "npm_and_yarn",
                  requirements: []
                )
              end
            end
          end

          dependency_set
        end

        sig do
          params(
            dependency_name: String,
            requirement: T.nilable(String),
            _manifest_name: T.untyped
          )
            .returns(T.nilable(T::Hash[String, T.untyped]))
        end
        def details(dependency_name, requirement, _manifest_name)
          details_candidates =
            parsed
            .select { |k, _| k.split(/(?<=\w)\@/)[0] == dependency_name }

          # If there's only one entry for this dependency, use it, even if
          # the requirement in the lockfile doesn't match
          if details_candidates.one?
            T.must(details_candidates.first).last
          else
            details_candidates.find do |k, _|
              k.scan(/(?<=\w)\@(?:npm:)?([^\s,]+)/).flatten.include?(requirement)
            end&.last
          end
        end

        private

        sig { returns(T::Boolean) }
        def dealias_packages?
          @dealias_packages
        end

        sig { params(requirement: String).returns(T::Boolean) }
        def alias_package?(requirement)
          requirement.match?(/@npm:(.+@(?!npm))/)
        end

        # Examples:
        # - "my-fetch-factory@npm:fetch-factory@^0.0.1" → "fetch-factory"
        # - "my-pkg@npm:@scope/real-pkg@^1.0.0" → "@scope/real-pkg"
        sig { params(requirement: String).returns(T.nilable(String)) }
        def extract_real_name_from_yarn_alias(requirement)
          match = requirement.match(/@npm:(.+)$/)
          return nil unless match

          rest = T.must(match[1])
          if rest.start_with?("@")
            second_at = rest.index("@", 1)
            second_at ? rest[0...second_at] : rest
          else
            at_index = rest.index("@")
            at_index ? rest[0...at_index] : rest
          end
        end

        sig { params(requirement: String).returns(T::Boolean) }
        def workspace_package?(requirement)
          requirement.include?("@workspace:")
        end
      end
    end
  end
end
