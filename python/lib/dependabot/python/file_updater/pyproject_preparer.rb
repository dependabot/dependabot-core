# typed: strict
# frozen_string_literal: true

require "toml-rb"
require "sorbet-runtime"
require "dependabot/dependency"
require "dependabot/python/file_parser"
require "dependabot/python/file_updater"
require "dependabot/python/authed_url_builder"
require "dependabot/python/name_normaliser"
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
          @parsed_lockfile = T.let(nil, T.nilable(T::Hash[String, T.untyped]))
        end

        # For hosted Dependabot token will be nil since the credentials aren't present.
        # This is for those running Dependabot themselves and for dry-run.
        sig { params(credentials: T.nilable(T::Array[Dependabot::Credential])).void }
        def add_auth_env_vars(credentials)
          TomlRB.parse(@pyproject_content).dig("tool", "poetry", "source")&.each do |source|
            cred = credentials&.find { |c| c["index-url"] == source["url"] }
            next unless cred

            token = cred.fetch("token", nil)
            next unless token && token.count(":") == 1

            arr = token.split(":")
            # https://python-poetry.org/docs/configuration/#using-environment-variables
            name = source["name"]&.upcase&.gsub(/\W/, "_")
            ENV["POETRY_HTTP_BASIC_#{name}_USERNAME"] = arr[0]
            ENV["POETRY_HTTP_BASIC_#{name}_PASSWORD"] = arr[1]
          end
        end

        sig { params(requirement: String).returns(String) }
        def update_python_requirement(requirement)
          pyproject_object = TomlRB.parse(@pyproject_content)

          if (python_specification = pyproject_object.dig("tool", "poetry", "dependencies", "python"))
            python_req = Python::Requirement.new(python_specification)
            unless python_req.satisfied_by?(requirement)
              pyproject_object["tool"]["poetry"]["dependencies"]["python"] = "~#{requirement}"
            end
          end

          TomlRB.dump(pyproject_object)
        end

        sig { returns(String) }
        def sanitize
          # {{ name }} syntax not allowed
          pyproject_content
            .gsub(/\{\{.*?\}\}/, "something")
            .gsub('#{', "{")
        end

        sig { returns(String) }
        def remove_path_dependencies
          pyproject_object = TomlRB.parse(pyproject_content)
          poetry_object = pyproject_object.dig("tool", "poetry")

          return pyproject_content unless poetry_object

          remove_path_deps_from_dependency_types(poetry_object)
          remove_path_deps_from_groups(poetry_object)

          TomlRB.dump(pyproject_object)
        end

        sig { returns(T.nilable(String)) }
        def remove_path_dependencies_from_lockfile
          return nil unless lockfile

          lockfile_object = TomlRB.parse(T.must(lockfile).content)
          packages = lockfile_object["package"] || []

          # Remove packages with local sources that won't exist in Dependabot environment:
          # - directory: local directory paths
          # - file: local file paths (.whl, .tar.gz, etc.)
          # - url: direct file URLs (not package registry URLs)
          path_source_types = %w(directory file url)
          packages.reject! do |package|
            source_type = package.dig("source", "type")
            path_source_types.include?(source_type)
          end

          lockfile_object["package"] = packages
          TomlRB.dump(lockfile_object)
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          # If lockfile is malformed, return nil and let Poetry regenerate it
          nil
        end

        # rubocop:disable Metrics/PerceivedComplexity
        # rubocop:disable Metrics/AbcSize
        sig { params(dependencies: T::Array[Dependabot::Dependency]).returns(String) }
        def freeze_top_level_dependencies_except(dependencies)
          return pyproject_content unless lockfile

          pyproject_object = TomlRB.parse(pyproject_content)
          poetry_object = pyproject_object.dig("tool", "poetry")

          return pyproject_content unless poetry_object

          excluded_names = dependencies.map(&:name) + ["python"]

          Dependabot::Python::FileParser::PyprojectFilesParser::POETRY_DEPENDENCY_TYPES.each do |key|
            next unless poetry_object[key]

            source_types = %w(directory file url)
            poetry_object.fetch(key).each do |dep_name, _|
              next if excluded_names.include?(normalise(dep_name))

              locked_details = locked_details(dep_name)

              next unless (locked_version = locked_details&.fetch("version"))

              next if source_types.include?(locked_details.dig("source", "type"))

              if locked_details.dig("source", "type") == "git"
                poetry_object[key][dep_name] = {
                  "git" => locked_details.dig("source", "url"),
                  "rev" => locked_details.dig("source", "reference")
                }
                subdirectory = locked_details.dig("source", "subdirectory")
                poetry_object[key][dep_name]["subdirectory"] = subdirectory if subdirectory
              elsif poetry_object[key][dep_name].is_a?(Hash)
                poetry_object[key][dep_name]["version"] = locked_version
              elsif poetry_object[key][dep_name].is_a?(Array)
                # if it has multiple-constraints, locking to a single version is
                # going to result in a bad lockfile, ignore
                next
              else
                poetry_object[key][dep_name] = locked_version
              end
            end
          end

          TomlRB.dump(pyproject_object)
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity

        private

        sig { returns(String) }
        attr_reader :pyproject_content

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :lockfile

        sig { params(poetry_object: T::Hash[String, T.untyped]).void }
        def remove_path_deps_from_dependency_types(poetry_object)
          Dependabot::Python::FileParser::PyprojectFilesParser::POETRY_DEPENDENCY_TYPES.each do |key|
            next unless poetry_object[key]

            poetry_object[key].reject! { |_dep_name, dep_spec| path_dependency?(dep_spec) }
          end
        end

        sig { params(poetry_object: T::Hash[String, T.untyped]).void }
        def remove_path_deps_from_groups(poetry_object)
          groups = poetry_object["group"] || {}
          groups.each do |_group_name, group_spec|
            next unless group_spec.is_a?(Hash) && group_spec["dependencies"]

            group_spec["dependencies"].reject! { |_dep_name, dep_spec| path_dependency?(dep_spec) }
          end
        end

        sig { params(dep_spec: T.untyped).returns(T::Boolean) }
        def path_dependency?(dep_spec)
          dep_spec.is_a?(Hash) && !dep_spec["path"].nil?
        end

        sig { params(dep_name: String).returns(T.nilable(T::Hash[String, T.untyped])) }
        def locked_details(dep_name)
          parsed_lockfile.fetch("package")
                         .find { |d| d["name"] == normalise(dep_name) }
        end

        sig { params(name: String).returns(String) }
        def normalise(name)
          NameNormaliser.normalise(name)
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed_lockfile
          @parsed_lockfile ||= TomlRB.parse(lockfile&.content)
        end
      end
    end
  end
end
