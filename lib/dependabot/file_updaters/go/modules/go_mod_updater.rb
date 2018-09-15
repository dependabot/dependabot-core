# frozen_string_literal: true

require "dependabot/file_updaters/go/dep"

module Dependabot
  module FileUpdaters
    module Go
      module Modules
        class GoModUpdater
          def initialize(dependencies:, go_mod:)
            @dependencies = dependencies
            @go_mod = go_mod
          end

          def updated_go_mod_content
            @updated_go_mod_content ||=
              SharedHelpers.in_a_temporary_directory do
                File.write("go.mod", @go_mod.content)

                deps = @dependencies.map do |dep|
                  {
                    name: dep.name,
                    version: dep.version,
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

          private

          def go_helper_path
            File.join(project_root, "helpers/go/updater/updater")
          end

          def project_root
            File.join(File.dirname(__FILE__), "../../../../..")
          end
        end
      end
    end
  end
end
