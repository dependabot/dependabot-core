# typed: strict
# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/uv/file_parser"
require "dependabot/errors"
require "dependabot/uv/name_normaliser"

module Dependabot
  module Uv
    class FileParser
      class PyprojectFilesParser
        extend T::Sig

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependency_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          dependency_set += pep621_pep735_dependencies if using_pep621? || using_pep735?

          dependency_set
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def pep621_pep735_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

          # PDM is not yet supported, so we want to ignore it for now because in
          # the current state of things, going on would result in updating
          # pyproject.toml but leaving pdm.lock out of sync, which is
          # undesirable. Leave PDM alone until properly supported
          return dependencies if using_pdm?

          parse_pep621_pep735_dependencies.each do |dep|
            # If a requirement has a `<` or `<=` marker then updating it is
            # probably blocked. Ignore it.
            next if dep["markers"]&.include?("<")

            # In uv no constraint means any version is acceptable
            requirement_value = dep["requirement"] && dep["requirement"].empty? ? "*" : dep["requirement"]

            dependencies <<
              Dependency.new(
                name: normalised_name(dep["name"], dep["extras"]),
                version: dep["version"]&.include?("*") ? nil : dep["version"],
                requirements: [{
                  requirement: requirement_value,
                  file: Pathname.new(dep["file"]).cleanpath.to_path,
                  source: nil,
                  groups: [dep["requirement_type"]].compact
                }],
                package_manager: "uv"
              )
          end

          dependencies
        end

        sig { params(name: String, extras: T::Array[String]).returns(String) }
        def normalised_name(name, extras)
          NameNormaliser.normalise_including_extras(name, extras)
        end

        sig { returns(T::Boolean) }
        def using_pep621?
          !parsed_pyproject.dig("project", "dependencies").nil? ||
            !parsed_pyproject.dig("project", "optional-dependencies").nil? ||
            !parsed_pyproject.dig("build-system", "requires").nil?
        end

        sig { returns(T::Boolean) }
        def using_pep735?
          parsed_pyproject.key?("dependency-groups")
        end

        sig { returns(T.untyped) }
        def using_pdm?
          using_pep621? && pdm_lock
        end

        sig { returns(T.untyped) }
        def parsed_pyproject
          @parsed_pyproject ||= T.let(TomlRB.parse(T.must(pyproject).content), T.untyped)
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          raise Dependabot::DependencyFileNotParseable, T.must(pyproject).path
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pyproject
          @pyproject ||= T.let(
            dependency_files.find { |f| f.name == "pyproject.toml" },
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { returns(T.untyped) }
        def parse_pep621_pep735_dependencies
          SharedHelpers.in_a_temporary_directory do
            write_temporary_pyproject

            SharedHelpers.run_helper_subprocess(
              command: "pyenv exec python3 #{NativeHelpers.python_helper_path}",
              function: "parse_pep621_pep735_dependencies",
              args: [T.must(pyproject).name]
            )
          end
        end

        sig { returns(Integer) }
        def write_temporary_pyproject
          path = T.must(pyproject).name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, T.must(pyproject).content)
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pdm_lock
          @pdm_lock ||= T.let(
            dependency_files.find { |f| f.name == "pdm.lock" },
            T.nilable(Dependabot::DependencyFile)
          )
        end
      end
    end
  end
end
