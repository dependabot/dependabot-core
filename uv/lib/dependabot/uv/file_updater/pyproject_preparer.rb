# typed: true
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
        def initialize(pyproject_content:, lockfile: nil)
          @pyproject_content = pyproject_content
          @lockfile = lockfile
          @lines = pyproject_content.split("\n")
        end

        def update_python_requirement(python_version)
          return @pyproject_content unless python_version

          in_project_table = false
          updated_lines = @lines.map.with_index do |line, _i|
            if line.match?(/^\[project\]/)
              in_project_table = true
              line
            elsif in_project_table && line.match?(/^requires-python\s*=/)
              "requires-python = \">=#{python_version}\""
            else
              line
            end
          end

          @pyproject_content = updated_lines.join("\n")
        end

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

        def sanitize
          # No special sanitization needed for UV files at this point
          @pyproject_content
        end

        private

        attr_reader :lockfile

        def sanitize_env_name(url)
          url.gsub(%r{^https?://}, "").gsub(/[^a-zA-Z0-9]/, "_").upcase
        end
      end
    end
  end
end
