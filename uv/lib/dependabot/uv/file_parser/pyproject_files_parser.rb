# typed: strict
# frozen_string_literal: true

require "toml-rb"

require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/uv/file_parser"
require "dependabot/uv/requirement"
require "dependabot/errors"
require "dependabot/uv/name_normaliser"

module Dependabot
  module Uv
    class FileParser
      class PyprojectFilesParser
        extend T::Sig

        UNSUPPORTED_DEPENDENCY_TYPES = %w(git path url).freeze

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependency_set
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new
          dependency_set += pyproject_dependencies if using_pep621? || using_pep735?
          dependency_set
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def pyproject_dependencies
          pep621_pep735_dependencies
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def pep621_pep735_dependencies
          dependencies = Dependabot::FileParsers::Base::DependencySet.new

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

        # @param req can be an Array, Hash or String that represents the constraints for a dependency
        sig { params(req: T.untyped, type: String).returns(T::Array[T::Hash[Symbol, T.nilable(String)]]) }
        def parse_requirements_from(req, type)
          [req].flatten.compact.filter_map do |requirement|
            next if requirement.is_a?(Hash) && UNSUPPORTED_DEPENDENCY_TYPES.intersect?(requirement.keys)

            check_requirements(requirement)

            if requirement.is_a?(String)
              {
                requirement: requirement,
                file: T.must(pyproject).name,
                source: nil,
                groups: [type]
              }
            else
              {
                requirement: requirement["version"],
                file: T.must(pyproject).name,
                source: requirement.fetch("source", nil),
                groups: [type]
              }
            end
          end
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

        sig { params(req: T.untyped).returns(T::Array[Dependabot::Uv::Requirement]) }
        def check_requirements(req)
          requirement = req.is_a?(String) ? req : req["version"]
          Uv::Requirement.requirements_array(requirement)
        rescue Gem::Requirement::BadRequirementError => e
          raise Dependabot::DependencyFileNotEvaluatable, e.message
        end

        sig { params(name: String).returns(String) }
        def normalise(name)
          NameNormaliser.normalise(name)
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
      end
    end
  end
end
