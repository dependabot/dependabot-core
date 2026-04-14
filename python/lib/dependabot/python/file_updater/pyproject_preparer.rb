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

        # Fixed regex for extracting the name+extras prefix from a PEP 508 entry.
        # Does not interpolate library input, avoiding polynomial backtracking.
        PEP508_PREFIX = T.let(
          /\A(?<prefix>(?<name>[a-zA-Z0-9](?:[a-zA-Z0-9._-]*[a-zA-Z0-9])?)(?:\[[^\]]*\])?)/i,
          Regexp
        )

        # Pins a single PEP 508 dependency entry string to a specific version,
        # preserving extras and environment markers.
        sig { params(entry: String, version: String).returns(String) }
        def self.pin_pep508_entry(entry, version)
          m = entry.match(PEP508_PREFIX)
          return entry unless m

          prefix = T.must(m[:prefix])
          rest = T.must(entry[prefix.length..])

          # Extract the environment marker ("; ..." suffix) if present
          marker_match = rest.match(/(\s*;.*)/)
          marker = marker_match ? marker_match[1] : ""

          "#{prefix}==#{version}#{marker}"
        end
        private_class_method :pin_pep508_entry

        # Freezes PEP 621 dependencies in-place within a parsed pyproject object.
        # Replaces version specifiers with ==dep.version for each matching dep.
        # Accepts an optional block to filter which dependencies to freeze.
        sig do
          params(
            pyproject_object: T::Hash[String, T.untyped],
            deps: T::Array[Dependabot::Dependency],
            blk: T.nilable(T.proc.params(dep: Dependabot::Dependency).returns(T::Boolean))
          ).void
        end
        def self.freeze_pep621_deps!(pyproject_object, deps, &blk)
          dep_arrays = collect_pep621_dep_arrays(pyproject_object)
          return if dep_arrays.empty?

          deps.each do |dep|
            next if blk && !yield(dep)
            next unless dep.version

            pin_pep621_dep_in_arrays!(dep_arrays, dep)
          end
        end

        sig { params(pyproject_object: T::Hash[String, T.untyped]).returns(T::Array[T::Array[String]]) }
        def self.collect_pep621_dep_arrays(pyproject_object)
          project_object = pyproject_object["project"]
          return [] unless project_object

          dep_arrays = [project_object["dependencies"]]
          project_object["optional-dependencies"]&.each_value { |opt| dep_arrays << opt }
          dep_arrays.compact!
          dep_arrays.select! { |arr| arr.is_a?(Array) && arr.all?(String) }
          dep_arrays
        end
        private_class_method :collect_pep621_dep_arrays

        sig { params(dep_arrays: T::Array[T::Array[String]], dep: Dependabot::Dependency).void }
        def self.pin_pep621_dep_in_arrays!(dep_arrays, dep)
          normalised_name = NameNormaliser.normalise(dep.name)
          dep_arrays.each do |arr|
            arr.each_with_index do |entry, i|
              match = entry.match(PEP508_PREFIX)
              next unless match
              next unless NameNormaliser.normalise(T.must(match[:name])) == normalised_name

              arr[i] = pin_pep508_entry(entry, T.must(dep.version))
            end
          end
        end
        private_class_method :pin_pep621_dep_in_arrays!

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

        UNSUPPORTED_SOURCE_TYPES = T.let(%w(directory file url).freeze, T::Array[String])

        sig { params(dependencies: T::Array[Dependabot::Dependency]).returns(String) }
        def freeze_top_level_dependencies_except(dependencies)
          return pyproject_content unless lockfile

          pyproject_object = TomlRB.parse(pyproject_content)
          poetry_object = pyproject_object.dig("tool", "poetry")

          return pyproject_content unless poetry_object

          excluded_names = dependencies.map(&:name) + ["python"]

          Dependabot::Python::FileParser::PyprojectFilesParser::POETRY_DEPENDENCY_TYPES.each do |key|
            next unless poetry_object[key]

            poetry_object.fetch(key).each do |dep_name, _|
              next if excluded_names.include?(normalise(dep_name))

              freeze_poetry_dep!(poetry_object[key], dep_name)
            end
          end

          # Freeze PEP 621 project.dependencies and project.optional-dependencies
          freeze_pep621_top_level_deps!(pyproject_object, excluded_names)

          TomlRB.dump(pyproject_object)
        end

        private

        sig { returns(String) }
        attr_reader :pyproject_content

        sig { returns(T.nilable(Dependabot::DependencyFile)) }
        attr_reader :lockfile

        sig { params(deps_hash: T::Hash[String, T.untyped], dep_name: String).void }
        def freeze_poetry_dep!(deps_hash, dep_name)
          details = locked_details(dep_name)
          return unless (locked_version = details&.fetch("version"))

          source_type = details.dig("source", "type")
          return if UNSUPPORTED_SOURCE_TYPES.include?(source_type)

          if source_type == "git"
            freeze_git_dep!(deps_hash, dep_name, details)
          elsif deps_hash[dep_name].is_a?(Hash)
            deps_hash[dep_name]["version"] = locked_version
          elsif !deps_hash[dep_name].is_a?(Array)
            deps_hash[dep_name] = locked_version
          end
        end

        sig { params(deps_hash: T::Hash[String, T.untyped], dep_name: String, details: T::Hash[String, T.untyped]).void }
        def freeze_git_dep!(deps_hash, dep_name, details)
          deps_hash[dep_name] = {
            "git" => details.dig("source", "url"),
            "rev" => details.dig("source", "reference")
          }
          subdirectory = details.dig("source", "subdirectory")
          deps_hash[dep_name]["subdirectory"] = subdirectory if subdirectory
        end

        sig { params(pyproject_object: T::Hash[String, T.untyped], excluded_names: T::Array[String]).void }
        def freeze_pep621_top_level_deps!(pyproject_object, excluded_names)
          project_object = pyproject_object["project"]
          return unless project_object

          freeze_pep621_dep_array!(project_object["dependencies"], excluded_names)

          project_object["optional-dependencies"]&.each_value do |opt_deps|
            freeze_pep621_dep_array!(opt_deps, excluded_names)
          end
        end

        sig { params(dep_array: T.nilable(T::Array[String]), excluded_names: T::Array[String]).void }
        def freeze_pep621_dep_array!(dep_array, excluded_names)
          return unless dep_array

          dep_array.each_with_index do |entry, index|
            # Extract dependency name from PEP 508 string
            match = entry.match(/\A([a-zA-Z0-9](?:[a-zA-Z0-9._-]*[a-zA-Z0-9])?)/i)
            next unless match

            dep_name = normalise(T.must(match[1]))
            next if excluded_names.include?(dep_name)

            locked_details = locked_details(dep_name)
            next unless (locked_version = locked_details&.fetch("version"))

            dep_array[index] = self.class.send(:pin_pep508_entry, entry, locked_version)
          end
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
