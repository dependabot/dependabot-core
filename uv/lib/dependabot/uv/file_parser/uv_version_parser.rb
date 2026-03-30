# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "dependabot/dependency"
require "dependabot/file_parsers/base/dependency_set"
require "dependabot/uv/file_parser"
require "dependabot/uv/requirement"

module Dependabot
  module Uv
    class FileParser
      # Parses the `required-version` field from `uv.toml` and
      # `[tool.uv]` in `pyproject.toml` to track the pinned uv tool version.
      class UvVersionParser
        extend T::Sig

        UV_TOOL_DEP_NAME = "uv"

        sig { params(dependency_files: T::Array[Dependabot::DependencyFile]).void }
        def initialize(dependency_files:)
          @dependency_files = dependency_files
        end

        sig { returns(Dependabot::FileParsers::Base::DependencySet) }
        def dependency_set
          deps = Dependabot::FileParsers::Base::DependencySet.new

          uv_toml_dep = parse_from_uv_toml
          deps << uv_toml_dep if uv_toml_dep

          pyproject_dep = parse_from_pyproject
          deps << pyproject_dep if pyproject_dep

          deps
        end

        private

        sig { returns(T::Array[Dependabot::DependencyFile]) }
        attr_reader :dependency_files

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def parse_from_uv_toml
          file = uv_toml_file
          return unless file

          parsed = TomlRB.parse(T.must(file.content))
          required_version = parsed["required-version"]
          return unless required_version.is_a?(String) && !required_version.empty?

          build_dependency(required_version, file.name)
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          nil
        end

        sig { returns(T.nilable(Dependabot::Dependency)) }
        def parse_from_pyproject
          return unless pyproject

          parsed = TomlRB.parse(T.must(T.must(pyproject).content))
          required_version = parsed.dig("tool", "uv", "required-version")
          return unless required_version.is_a?(String) && !required_version.empty?

          build_dependency(required_version, T.must(pyproject).name)
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          nil
        end

        sig { params(requirement_string: String, filename: String).returns(Dependabot::Dependency) }
        def build_dependency(requirement_string, filename)
          Dependabot::Dependency.new(
            name: UV_TOOL_DEP_NAME,
            version: extract_exact_version(requirement_string),
            requirements: [{
              requirement: requirement_string,
              file: filename,
              source: nil,
              groups: ["uv-required-version"]
            }],
            package_manager: "uv"
          )
        end

        sig { params(requirement_string: String).returns(T.nilable(String)) }
        def extract_exact_version(requirement_string)
          reqs = Requirement.requirements_array(requirement_string)
          return nil unless reqs.length == 1

          req = T.must(reqs.first)
          return nil unless req.exact?

          req.requirements.first&.last&.to_s
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def uv_toml_file
          @uv_toml_file ||= T.let(
            dependency_files.find { |f| f.name == "uv.toml" },
            T.nilable(Dependabot::DependencyFile)
          )
        end

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        def pyproject
          @pyproject ||= T.let(
            dependency_files.find { |f| f.name == "pyproject.toml" },
            T.nilable(Dependabot::DependencyFile)
          )
        end
      end
    end
  end
end
