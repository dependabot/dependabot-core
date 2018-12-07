# frozen_string_literal: true

require "dependabot/python/file_updater"
require "dependabot/python/file_parser/setup_file_parser"

module Dependabot
  module Python
    class FileUpdater
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
            "install_requires=#{install_requires_array.to_json},"\
            "extras_require=#{extras_require_hash.to_json}"

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
            parsed_setup_file.dependencies.map do |dep|
              next unless dep.requirements.first[:groups].
                          include?("install_requires")

              dep.name + dep.requirements.first[:requirement].to_s
            end.compact
        end

        def setup_requires_array
          @setup_requires_array ||=
            parsed_setup_file.dependencies.map do |dep|
              next unless dep.requirements.first[:groups].
                          include?("setup_requires")

              dep.name + dep.requirements.first[:requirement].to_s
            end.compact
        end

        def extras_require_hash
          @extras_require_hash ||=
            begin
              hash = {}
              parsed_setup_file.dependencies.each do |dep|
                dep.requirements.first[:groups].each do |group|
                  next unless group.start_with?("extras_require:")

                  hash[group.split(":").last] ||= []
                  hash[group.split(":").last] <<
                    dep.name + dep.requirements.first[:requirement].to_s
                end
              end

              hash
            end
        end

        def parsed_setup_file
          @parsed_setup_file ||=
            FileParsers::Python::Pip::SetupFileParser.new(
              dependency_files: [
                setup_file&.dup&.tap { |f| f.name = "setup.py" },
                setup_cfg&.dup&.tap { |f| f.name = "setup.cfg" }
              ].compact
            ).dependency_set
        end
      end
    end
  end
end
