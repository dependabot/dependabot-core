# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/paket/file_parser"

# For details on global.json files see:
# https://docs.microsoft.com/en-us/dotnet/core/tools/global-json
module Dependabot
  module Paket
    class FileParser
      class PaketLockfileParser

        require "dependabot/file_parsers/base/dependency_set"

        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def parse
          dependency_set = Dependabot::Paket::FileParser::DependencySet.new
          dependency_set += paket_lock_dependencies if paket_dependencies.any?
          dependency_set.dependencies
        end

        private

        def paket_lock_dependencies
          dependency_set = Dependabot::Paket::FileParser::DependencySet.new

          paket_dependencies.each do |paket_dependency|
            paket_lock = paket_locks.find{|i| i.directory.eql? paket_dependency.directory}
            parse_paket_dependency_and_lock(paket_dependency, paket_lock).each do |details|
              # next unless semver_version_for(details["version"])
              # next if alias_package?(req)

              dependency_set << Dependency.new(
                name: details["packageName"],
                version: details["packageVersion"],
                package_manager: "paket",
                requirements: [{
                  requirement: details["packageRequirement"],
                  file: paket_lock.name,
                  groups: [details["groupName"]],
                  source: nil
                }]
              )
            end
          end

          dependency_set
        end

        def parse_paket_dependency_and_lock(paket_dependencies, paket_lock)
          @parsed_paket_dependencies ||= {}
          @parsed_paket_dependencies[paket_dependencies.name] ||=
            SharedHelpers.in_a_temporary_directory do
              File.write("paket.dependencies", paket_dependencies.content)
              File.write("paket.lock", paket_lock.content)
              cmd = "dotnet %s" % [NativeHelpers.helper_path]
              SharedHelpers.run_helper_subprocess(
                command: cmd,
                function: "parseLockfile",
                args: {"dependencyPath" => Dir.pwd}
              )
            rescue SharedHelpers::HelperSubprocessFailed => ex
              $stderr.puts ex
              raise Dependabot::DependencyFileNotParseable, paket_lock.path
            end
        end

        def paket_dependencies
          @paket_dependencies ||=
            @dependency_files.
            select { |f| f.name.end_with?("paket.dependencies") }
        end


        def paket_locks
          @paket_locks ||=
            @dependency_files.
            select { |f| f.name.end_with?("paket.lock") }
        end

      end
    end
  end
end
