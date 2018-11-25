# frozen_string_literal: true

require "cocoapods-core"
require "dependabot/dependency"
require "dependabot/file_parsers/base"

module Dependabot
  module FileParsers
    module Cocoa
      class CocoaPods < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/base/dependency_set"

        def parse
          dependency_set = DependencySet.new
          dependency_set += podfile_dependencies
          dependency_set += lockfile_dependencies
          dependency_set.dependencies
        end

        private

        def podfile_dependencies
          dependencies = DependencySet.new

          parsed_podfile.dependencies.each do |dep|
            # Ignore dependencies with multiple requirements, since they would
            # cause trouble at the gem update step
            next if dep.requirement.requirements.count > 1

            dependencies <<
              Dependency.new(
                name: dep.name,
                version: dependency_version(dep.name)&.to_s,
                requirements: [{
                  requirement: dep.requirement.to_s,
                  groups: [],
                  source: nil, # TODO: Identify git dependencies
                  file: podfile.name
                }],
                package_manager: "cocoapods"
              )
          end

          dependencies
        end

        def lockfile_dependencies
          dependencies = DependencySet.new

          # TODO: Add dependencies from lockfile here (their requirements should
          # be an empty array)

          dependencies
        end

        def check_required_files
          raise "No Podfile!" unless podfile
          raise "No Podfile.lock!" unless lockfile
        end

        def dependency_version(dependency_name)
          Gem::Version.new(parsed_lockfile.version(dependency_name))
        end

        def podfile
          @podfile ||= get_original_file("Podfile")
        end

        def lockfile
          @lockfile ||= get_original_file("Podfile.lock")
        end

        def parsed_podfile
          @parsed_podfile ||= Pod::Podfile.from_ruby(nil, podfile.content)
        end

        def parsed_lockfile
          @parsed_lockfile ||=
            begin
              lockfile_hash = Pod::YAMLHelper.load_string(lockfile.content)
              Pod::Lockfile.new(lockfile_hash)
            end
        end
      end
    end
  end
end
