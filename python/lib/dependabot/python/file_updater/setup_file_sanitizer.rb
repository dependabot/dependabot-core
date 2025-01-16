# typed: strict
# frozen_string_literal: true

require "dependabot/python/file_updater"
require "dependabot/python/file_parser/setup_file_parser"
require "sorbet-runtime"

module Dependabot
  module Python
    class FileUpdater
      # Take a setup.py, parses it (carefully!) and then create a new, clean
      # setup.py using only the information which will appear in the lockfile.
      class SetupFileSanitizer
        extend T::Sig

        sig { params(setup_file: DependencyFile, setup_cfg: T.untyped).void }
        def initialize(setup_file:, setup_cfg:)
          @setup_file = setup_file
          @setup_cfg = setup_cfg
        end

        sig { returns(String) }
        def sanitized_content
          # The part of the setup.py that Pipenv cares about appears to be the
          # install_requires. A name and version are required by don't end up
          # in the lockfile.
          content =
            "from setuptools import setup\n\n" \
            "setup(name=\"#{package_name}\",version=\"0.0.1\"," \
            "install_requires=#{install_requires_array.to_json}," \
            "extras_require=#{extras_require_hash.to_json}"

          content += ',setup_requires=["pbr"],pbr=True' if include_pbr?
          content + ")"
        end

        private

        sig { returns(DependencyFile) }
        attr_reader :setup_file
        sig { returns(String) }
        attr_reader :setup_cfg

        sig { returns(T::Boolean) }
        def include_pbr?
          setup_requires_array.any? { |d| d.start_with?("pbr") }
        end

        sig { returns(T.untyped) }
        def install_requires_array
          @install_requires_array = T.let(T.untyped, T.untyped)
          @install_requires_array ||=
            parsed_setup_file.dependencies.filter_map do |dep|
              next unless dep.requirements.first[:groups]
                             .include?("install_requires")

              dep.name + dep.requirements.first[:requirement].to_s
            end
        end

        sig { returns(T::Array[String]) }
        def setup_requires_array
          @setup_requires_array = T.let(T.untyped, T.untyped)
          @setup_requires_array ||=
            parsed_setup_file.dependencies.filter_map do |dep|
              next unless dep.requirements.first[:groups]
                             .include?("setup_requires")

              dep.name + dep.requirements.first[:requirement].to_s
            end
        ends

        sig { returns(T.untyped) }
        def extras_require_hash
          @extras_require_hash = T.let(Hash, T.untyped)
          @extras_require_hash ||=
            begin
              hash = {}
              parsed_setup_file.dependencies.each do |dep|
                dep.requirements.first[:groups].each do |group|
                  next unless group.start_with?("extras_require:")

                  hash[group.split(":").last] ||= []
                  hash[group.split(":").last] <<
                    (dep.name + dep.requirements.first[:requirement].to_s)
                end
              end

              hash
            end
        end

        sig { returns(T.untyped) }
        def parsed_setup_file
          @parsed_setup_file ||= T.let(Python::FileParser::SetupFileParser.new(
            dependency_files: [
              setup_file.dup.tap { |f| f.name = "setup.py" },
              setup_cfg.dup.tap { |f| f.name = "setup.cfg" }
            ].compact
          )
            .dependency_set, T.untyped)
        end

        sig { returns(T.nilable(String)) }
        def package_name
          content = setup_file.content
          match = T.must(content).match(/name\s*=\s*['"](?<package_name>[^'"]+)['"]/)
          match ? match[:package_name] : "default_package_name"
        end
      end
    end
  end
end
