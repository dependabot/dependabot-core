# typed: strong
# frozen_string_literal: true

require "toml-rb"
require "citrus"

require "dependabot/dependency"
require "dependabot/uv/file_parser"
require "dependabot/uv/file_updater"
require "dependabot/uv/authed_url_builder"
require "dependabot/uv/name_normaliser"
require "securerandom"

module Dependabot
  module Uv
    class FileUpdater
      class PyprojectPreparer
        extend T::Sig

        sig { params(pyproject_content: String, lockfile: T.nilable(Dependabot::DependencyFile)).void }
        def initialize(pyproject_content:, lockfile: nil)
          @pyproject_content = pyproject_content
          @lockfile = lockfile
          @lines = T.let(pyproject_content.split("\n"), T::Array[String])
        end

        sig { params(python_version: T.nilable(String)).returns(String) }
        def update_python_requirement(python_version)
          return @pyproject_content unless python_version

          in_project_table = T.let(false, T::Boolean)
          updated_lines = @lines.map do |line|
            in_project_table = true if line.match?(/^\[project\]/)

            if in_project_table && line.match?(/^requires-python\s*=/)
              "requires-python = \">=#{python_version}\""
            else
              line
            end
          end

          @pyproject_content = updated_lines.join("\n")
        end

        sig { returns(String) }
        def sanitize
          # No special sanitization needed for UV files at this point
          @pyproject_content
        end

        private

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :lockfile
      end
    end
  end
end
