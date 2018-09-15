# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/file_parsers/python/pip"
require "dependabot/errors"

module Dependabot
  module FileParsers
    module Go
      class GoModParser
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        def dependency_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new
          dependency_set += go_mod_dependencies
          dependency_set
        end

        private

        attr_reader :dependency_files

        def go_mod_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          i = 0
          chunks = module_info(go_mod).lines.group_by do |line|
            if line == "{\n"
              i += 1
            else
              i
            end
          end
          deps = chunks.values.map { |chunk| JSON.parse(chunk.join) }

          deps.each do |dep|
            # The project itself appears in this list as "Main"
            next if dep["Main"]

            reqs = [{
              requirement: dep["Indirect"] ? nil : dep["Version"],
              file: go_mod.name,
              source: { # TODO
                type: "default",
                source: dep["Path"]
              },
              groups: []
            }]
            dependencies <<
              Dependency.new(
                name: dep["Path"],
                version: dep["Version"],
                requirements: dep["Indirect"] ? [] : reqs,
                package_manager: "go" # TODO
              )
          end

          dependencies
        end

        def version_from_lockfile(dep_name)
          return unless pyproject_lock

          parsed_pyproject_lock.fetch("package", []).
            find { |p| p.fetch("name") == normalised_name(dep_name) }&.
            fetch("verison", nil)
        end

        def module_info(go_mod)
          # TODO go.sum
          @module_info ||=
            SharedHelpers.in_a_temporary_directory do
              File.write("go.mod", go_mod.content)

              output = %x[GO111MODULE=on go list -m -json all]
              unless $CHILD_STATUS.success?
                raise Dependabot::DependencyFileNotParseable, go_mod.path
              end
              output
            end
        end

        def go_mod
          @go_mod ||=
            dependency_files.find { |f| f.name == "go.mod" }
        end
      end
    end
  end
end
