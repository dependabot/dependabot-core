# frozen_string_literal: true

require "dependabot/file_updaters/go/modules"

module Dependabot
  module FileUpdaters
    module Go
      class Modules
        class GoModUpdater
          def initialize(dependencies:, go_mod:, go_sum:, credentials:)
            @dependencies = dependencies
            @go_mod = go_mod
            @go_sum = go_sum
            @credentials = credentials
          end

          def updated_go_mod_content
            @updated_go_mod_content ||=
              SharedHelpers.in_a_temporary_directory do
                SharedHelpers.with_git_configured(credentials: credentials) do
                  File.write("go.mod", go_mod.content)

                  deps = dependencies.map do |dep|
                    {
                      name: dep.name,
                      version: "v" + dep.version.sub(/^v/i, ""),
                      indirect: dep.requirements.empty?
                    }
                  end

                  SharedHelpers.run_helper_subprocess(
                    command: go_helper_path,
                    function: "updateDependencyFile",
                    args: { dependencies: deps }
                  )
                end
              end
          end

          def updated_go_sum_content
            return nil unless go_sum

            # This needs to be run separately so we don't nest subprocess calls
            updated_go_mod_content

            @updated_go_sum_content ||=
              SharedHelpers.in_a_temporary_directory do
                SharedHelpers.with_git_configured(credentials: credentials) do
                  File.write("go.mod", updated_go_mod_content)
                  File.write("go.sum", go_sum.content)

                  `GO111MODULE=on go get`
                  unless $CHILD_STATUS.success?
                    raise Dependabot::DependencyFileNotParseable, go_sum.path
                  end

                  File.read("go.sum")
                end
              end
          end

          private

          attr_reader :dependencies, :go_mod, :go_sum, :credentials

          def go_helper_path
            File.join(project_root, "helpers/go/go-helpers.#{platform}64")
          end

          def project_root
            File.join(File.dirname(__FILE__), "../../../../..")
          end

          def platform
            case RbConfig::CONFIG["arch"]
            when /linux/ then "linux"
            when /darwin/ then "darwin"
            else raise "Invalid platform #{RbConfig::CONFIG['arch']}"
            end
          end
        end
      end
    end
  end
end
