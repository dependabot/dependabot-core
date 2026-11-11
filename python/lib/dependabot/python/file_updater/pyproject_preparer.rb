# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/python/file_parser"
require "dependabot/python/file_parser/poetry_lock"
require "dependabot/python/file_parser/pyproject_document"
require "dependabot/python/file_updater"
require "dependabot/python/authed_url_builder"
require "securerandom"

module Dependabot
  module Python
    class FileUpdater
      class PyprojectPreparer
        extend T::Sig

        sig { params(pyproject_content: String, lockfile: T.nilable(Dependabot::DependencyFile)).void }
        def initialize(pyproject_content:, lockfile: nil)
          @pyproject_content = pyproject_content
          @lockfile = lockfile
        end

        # For hosted Dependabot token will be nil since the credentials aren't present.
        # This is for those running Dependabot themselves and for dry-run.
        sig { params(credentials: T.nilable(T::Array[Dependabot::Credential])).void }
        def add_auth_env_vars(credentials)
          return if credentials.nil? || credentials.empty?

          auth_environment(credentials).each { |key, value| ENV[key] = value }
        end

        sig { params(requirement: String).returns(String) }
        def update_python_requirement(requirement)
          document = FileParser::PyprojectDocument.from_content(@pyproject_content)
          document.update_python_requirement(requirement)
          document.to_toml
        end

        sig { returns(String) }
        def sanitize
          # {{ name }} syntax not allowed
          pyproject_content
            .gsub(/\{\{.*?\}\}/, "something")
            .gsub('#{', "{")
        end

        sig { params(dependencies: T::Array[Dependabot::Dependency]).returns(String) }
        def freeze_top_level_dependencies_except(dependencies)
          return pyproject_content unless lockfile

          document = FileParser::PyprojectDocument.from_content(pyproject_content)
          return pyproject_content unless document.poetry? || document.poetry_build_backend?

          lock = FileParser::PoetryLock.from_content(T.must(T.must(lockfile).content))
          excluded_names = dependencies.map(&:name) + ["python"]
          document.freeze_poetry_dependencies(lock: lock, excluding: excluded_names)
          document.freeze_locked_pep621_dependencies(lock: lock, excluding: excluded_names)
          document.to_toml
        end

        private

        sig { params(credentials: T::Array[Dependabot::Credential]).returns(T::Hash[String, T.nilable(String)]) }
        def auth_environment(credentials)
          assignments = T.let({}, T::Hash[String, T.nilable(String)])
          FileParser::PyprojectDocument.from_content(@pyproject_content).poetry_auth_sources.each do |source|
            url = source.url
            cred = credentials.find { |c| c["index-url"] == url }
            next unless cred

            token = cred["token"]
            next unless token && token.count(":") == 1

            arr = token.split(":")
            # https://python-poetry.org/docs/configuration/#using-environment-variables
            name = source.name&.upcase&.gsub(/\W/, "_")
            assignments["POETRY_HTTP_BASIC_#{name}_USERNAME"] = arr[0]
            assignments["POETRY_HTTP_BASIC_#{name}_PASSWORD"] = arr[1]
          end
          assignments
        end

        sig { returns(String) }
        attr_reader :pyproject_content

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :lockfile
      end
    end
  end
end
