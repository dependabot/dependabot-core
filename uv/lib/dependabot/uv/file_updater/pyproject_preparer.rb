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

        Credentials = T.type_alias { T::Array[T::Hash[String, String]] }

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

        sig { params(credentials: T.nilable(Credentials)).returns(T.nilable(Credentials)) }
        def add_auth_env_vars(credentials)
          return unless credentials

          credentials.each do |credential|
            next unless credential["type"] == "python_index"

            token = credential["token"]
            index_url = credential["index-url"]

            next unless token && index_url

            # Set environment variables for uv auth
            ENV["UV_INDEX_URL_TOKEN_#{sanitize_env_name(index_url)}"] = token

            # Also set pip-style credentials for compatibility
            ENV["PIP_INDEX_URL"] ||= "https://#{token}@#{index_url.gsub(%r{^https?://}, '')}"
          end
        end

        sig { returns(String) }
        def sanitize
          # No special sanitization needed for UV files at this point
          @pyproject_content
        end

        private

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :lockfile

        sig { params(url: String).returns(String) }
        def sanitize_env_name(url)
          url.gsub(%r{^https?://}, "").gsub(/[^a-zA-Z0-9]/, "_").upcase
        end
      end
    end
  end
end
