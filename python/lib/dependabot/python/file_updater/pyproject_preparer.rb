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

        # Matches the PEP 508 name part of a dependency entry string, including optional extras.
        # Example: "pillow==12.0.0" → "pillow", "celery[redis]==5.5.3" → "celery[redis]"
        PEP508_NAME_REGEX = /\A([A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?(?:\[[^\]]+\])?)/

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

          freeze_pep621_pep735_deps!(pyproject_object, excluded_names)

          TomlRB.dump(pyproject_object)
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Metrics/PerceivedComplexity

        private

        sig { returns(String) }
        attr_reader :pyproject_content

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :lockfile

        sig { params(dep_name: String).returns(T.nilable(T::Hash[String, T.untyped])) }
        def locked_details(dep_name)
          parsed_lockfile.fetch("package")
                         .find { |d| d["name"] == normalise(dep_name) }
        end

        sig { params(name: String).returns(String) }
        def normalise(name)
          NameNormaliser.normalise(name)
        end

        # Freeze PEP 621 and PEP 735 dependency entries to their locked versions.
        sig { params(pyproject_object: T::Hash[String, T.untyped], excluded_names: T::Array[String]).void }
        def freeze_pep621_pep735_deps!(pyproject_object, excluded_names)
          source_types = %w(directory file url)

          pep621_project = pyproject_object["project"]
          if pep621_project
            freeze_pep621_deps_array!(pep621_project.fetch("dependencies", []), excluded_names, source_types)
            (pep621_project["optional-dependencies"] || {}).each_value do |optional_deps|
              freeze_pep621_deps_array!(optional_deps, excluded_names, source_types)
            end
          end

          pyproject_object["dependency-groups"]&.each_value do |group_deps|
            freeze_pep621_deps_array!(group_deps, excluded_names, source_types) if group_deps.is_a?(Array)
          end
        end

        # Freeze PEP 621/735 array entries in-place to their locked versions,
        # skipping excluded deps, source deps, and entries without lock data.
        sig do
          params(
            deps_array: T::Array[T.untyped],
            excluded_names: T::Array[String],
            source_types: T::Array[String]
          ).void
        end
        def freeze_pep621_deps_array!(deps_array, excluded_names, source_types)
          # Normalize excluded names once for efficient comparison (strips extras)
          excluded_normalised = excluded_names.map { |n| normalise(n) }
          deps_array.each_with_index do |dep_entry, idx|
            next unless dep_entry.is_a?(String)

            # PEP 508 name part: letters/digits/._- with optional [extras]
            name_match = dep_entry.match(PEP508_NAME_REGEX)
            next unless name_match

            entry_pkg_name = T.must(name_match[1])
            next if excluded_normalised.include?(normalise(entry_pkg_name))

            locked = locked_details(entry_pkg_name)
            next unless locked

            locked_version = locked.fetch("version", nil)
            next unless locked_version
            next if source_types.include?(locked.dig("source", "type"))

            # Preserve environment markers such as "; python_version >= '3.10'"
            env_marker = dep_entry[/;.*\z/m] || ""
            deps_array[idx] = "#{entry_pkg_name}==#{locked_version}#{env_marker}"
          end
        end

        sig { returns(T::Hash[String, T.untyped]) }
        def parsed_lockfile
          @parsed_lockfile ||= TomlRB.parse(lockfile&.content)
        end
      end
    end
  end
end
