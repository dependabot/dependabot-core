# frozen_string_literal: true

require "json"
require "dependabot/shared_helpers"
require "dependabot/file_updaters/python/pip"

module Dependabot
  module FileUpdaters
    module Python
      class Pip
        # Take a setup.py, parses it (carefully!) and then create a new, clean
        # setup.py using only the information which will appear in the lockfile.
        class SetupFileSanitizer
          def initialize(setup_file:, setup_cfg:)
            @setup_file = setup_file
            @setup_cfg = setup_cfg
          end

          def sanitized_content
            # The part of the setup.py that Pipenv cares about appears to be the
            # install_requires. A name and version are required by don't end up
            # in the lockfile.
            content =
              "from setuptools import setup\n\n"\
              "setup(name=\"sanitized-package\",version=\"0.0.1\","\
              "install_requires=#{install_requires_array.to_json}"

            content += ',setup_requires=["pbr"],pbr=True' if include_pbr?
            content + ")"
          end

          private

          attr_reader :setup_file, :setup_cfg

          def include_pbr?
            setup_requires_array.any? { |d| d.start_with?("pbr") }
          end

          def install_requires_array
            @install_requires_array ||=
              parsed_setup_file.map do |dep|
                next unless dep["requirement_type"] == "install_requires"

                dep["name"] + dep["requirement"].to_s
              end.compact
          end

          def setup_requires_array
            @setup_requires_array ||=
              parsed_setup_file.map do |dep|
                next unless dep["requirement_type"] == "setup_requires"

                dep["name"] + dep["requirement"].to_s
              end.compact
          end

          def parsed_setup_file
            @parsed_setup_file ||=
              SharedHelpers.in_a_temporary_directory do
                write_temporary_files

                SharedHelpers.run_helper_subprocess(
                  command: "pyenv exec python #{python_helper_path}",
                  function: "parse_setup",
                  args: [Dir.pwd]
                )
              end
          end

          def write_temporary_files
            path = setup_file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, setup_file.content)

            return unless setup_cfg

            path = setup_cfg.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, setup_cfg.content)
          end

          def python_helper_path
            project_root = File.join(File.dirname(__FILE__), "../../../../..")
            File.join(project_root, "helpers/python/run.py")
          end
        end
      end
    end
  end
end
