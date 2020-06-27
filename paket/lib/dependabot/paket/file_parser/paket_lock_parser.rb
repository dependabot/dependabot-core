# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/paket/file_parser"

# For details on global.json files see:
# https://docs.microsoft.com/en-us/dotnet/core/tools/global-json
module Dependabot
  module Paket
    class FileParser
      class PaketLockParser

        require "dependabot/file_parsers/base/dependency_set"

        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def parse
          dependency_set = Dependabot::Paket::FileParser::DependencySet.new
          dependency_set += paket_lock_dependencies if paket_locks.any?
          dependency_set.dependencies
        end

        private

        def paket_lock_dependencies
          dependency_set = Dependabot::Paket::FileParser::DependencySet.new

          paket_locks.each do |paket_lock|
            # $stderr.puts parse_paket_lock(paket_lock)
            parse_paket_lock(paket_lock).each do |details|
              # next unless semver_version_for(details["version"])
              # next if alias_package?(req)

              # # Note: The DependencySet will de-dupe our dependencies, so they
              # # end up unique by name. That's not a perfect representation of
              # # the nested nature of JS resolution, but it makes everything work
              # # comparably to other flat-resolution strategies
              # dependency_set << Dependency.new(
              #   name: req.split(/(?<=\w)\@/).first,
              #   version: semver_version_for(details["version"]),
              #   package_manager: "npm_and_yarn",
              #   requirements: []
              # )
            end
          end

          dependency_set
        end

        def parse_paket_lock(paket_lock)
          @parsed_paket_lock ||= {}
          @parsed_paket_lock[paket_lock.name] ||=
            SharedHelpers.in_a_temporary_directory do
              File.write("paket.lock", paket_lock.content)
              cmd = "dotnet %s" % [NativeHelpers.helper_path]
              SharedHelpers.run_helper_subprocess(
                command: cmd,
                function: "parseLockfile",
                args: {"lockFilePath" => Dir.pwd}
              )
            rescue SharedHelpers::HelperSubprocessFailed => ex
              raise Dependabot::DependencyFileNotParseable, paket_lock.path
            end
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
