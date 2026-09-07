# typed: strong
# frozen_string_literal: true

require "toml-rb"
require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/python/file_parser"

module Dependabot
  module Python
    class FileParser < Dependabot::FileParsers::Base
      module PyprojectValueParser
        extend T::Sig

        ObjectHash = T.type_alias { T::Hash[String, Object] }
        PoetryRequirement = T.type_alias { T.any(String, ObjectHash) }
        PoetryDependencyMap = T.type_alias { T::Hash[String, T::Array[PoetryRequirement]] }

        sig { params(value: Object, context: String).returns(ObjectHash) }
        def self.object_hash(value, context)
          raise TypeError, "#{context} must be an object" unless value.is_a?(Hash)

          result = T.let({}, ObjectHash)
          value.each do |raw_key, raw_value|
            key = T.cast(raw_key, Object)
            raise TypeError, "#{context} keys must be strings" unless key.is_a?(String)

            result[key] = T.cast(raw_value, Object)
          end
          result
        end

        sig { params(value: Object, context: String).returns(T::Array[Object]) }
        def self.array(value, context)
          raise TypeError, "#{context} must be an array" unless value.is_a?(Array)

          value.map { |item| T.cast(item, Object) }
        end

        sig { params(value: Object, context: String).returns(String) }
        def self.string(value, context)
          return value if value.is_a?(String)

          raise TypeError, "#{context} must be a string"
        end

        sig { params(value: T.nilable(Object), context: String).returns(T.nilable(String)) }
        def self.optional_string(value, context)
          return if value.nil?

          string(value, context)
        end

        sig { params(value: Object, context: String).returns(T::Array[String]) }
        def self.string_array(value, context)
          array(value, context).map do |item|
            raise TypeError, "#{context} must contain only strings" unless item.is_a?(String)

            item
          end
        end

        sig { params(value: Object, name: String).returns(T::Array[PoetryRequirement]) }
        def self.poetry_requirements(value, name)
          flattened = value.is_a?(Array) ? value.flatten : [value]
          flattened.compact.map do |item|
            item = T.cast(item, Object)
            case item
            when String
              item
            when Hash
              object_hash(item, "Poetry dependency #{name}")
            else
              raise TypeError, "Poetry dependency #{name} must be a string, object, or array"
            end
          end
        end

        sig { params(value: Object, context: String).returns(PoetryDependencyMap) }
        def self.poetry_dependency_map(value, context)
          object_hash(value, context).to_h do |name, requirement|
            [name, poetry_requirements(requirement, name)]
          end
        end
      end
      private_constant :PyprojectValueParser

      class PyprojectDocument
        extend T::Sig

        PoetryRequirement = T.type_alias { PyprojectValueParser::PoetryRequirement }
        PoetryDependencyMap = T.type_alias { PyprojectValueParser::PoetryDependencyMap }

        class PoetrySource < T::ImmutableStruct
          const :name, String
          const :url, T.nilable(String), default: nil
        end

        class ProjectMetadata < T::ImmutableStruct
          const :name, T.nilable(String), default: nil
          const :description, T.nilable(String), default: nil
        end

        sig { params(data: PyprojectValueParser::ObjectHash).void }
        def initialize(data)
          @data = data
        end

        sig { params(file: Dependabot::DependencyFile).returns(PyprojectDocument) }
        def self.from_file(file)
          from_content(T.must(file.content))
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          raise Dependabot::DependencyFileNotParseable, file.path
        end

        sig { params(content: String).returns(PyprojectDocument) }
        def self.from_content(content)
          parsed = T.cast(TomlRB.parse(content), Object)
          new(PyprojectValueParser.object_hash(parsed, "pyproject.toml"))
        end

        sig { returns(T::Boolean) }
        def poetry?
          !poetry_root.nil?
        end

        sig { returns(T::Boolean) }
        def project?
          !section(@data, "project", "project").nil?
        end

        sig { returns(T.nilable(ProjectMetadata)) }
        def poetry_metadata
          metadata_from(poetry_root, "tool.poetry")
        end

        sig { returns(T.nilable(ProjectMetadata)) }
        def project_metadata
          metadata_from(section(@data, "project", "project"), "project")
        end

        sig { returns(T.nilable(ProjectMetadata)) }
        def build_system_metadata
          metadata_from(section(@data, "build-system", "build-system"), "build-system")
        end

        sig { returns(T::Boolean) }
        def pep621?
          project = section(@data, "project", "project")
          build_system = section(@data, "build-system", "build-system")

          !project&.[]("dependencies").nil? ||
            !project&.[]("optional-dependencies").nil? ||
            !build_system&.[]("requires").nil?
        end

        sig { returns(T::Boolean) }
        def pep735?
          @data.key?("dependency-groups")
        end

        sig { params(type: String).returns(PoetryDependencyMap) }
        def poetry_dependencies(type)
          root = poetry_root
          return {} unless root

          value = root[type]
          return {} if value.nil?

          PyprojectValueParser.poetry_dependency_map(value, "tool.poetry.#{type}")
        end

        sig { returns(T::Hash[String, PoetryDependencyMap]) }
        def poetry_groups
          root = poetry_root
          return {} unless root

          raw_groups = root["group"]
          return {} if raw_groups.nil?

          parsed_groups = PyprojectValueParser.object_hash(raw_groups, "tool.poetry.group")
          parsed_groups.each_with_object({}) do |(name, value), groups|
            group = PyprojectValueParser.object_hash(value, "tool.poetry.group.#{name}")
            dependencies = group["dependencies"]
            next if dependencies.nil?

            groups[name] = PyprojectValueParser.poetry_dependency_map(
              dependencies,
              "tool.poetry.group.#{name}.dependencies"
            )
          end
        end

        sig { returns(T::Array[String]) }
        def dynamic_fields
          project = section(@data, "project", "project")
          value = project&.[]("dynamic")
          return [] if value.nil?

          PyprojectValueParser.string_array(value, "project.dynamic")
        end

        sig { params(name: String).returns(T::Boolean) }
        def optional_dependency_group?(name)
          project = section(@data, "project", "project")
          value = project&.[]("optional-dependencies")
          return false if value.nil?

          PyprojectValueParser.object_hash(value, "project.optional-dependencies").key?(name)
        end

        sig { params(name: String).returns(T.nilable(PoetrySource)) }
        def poetry_source(name)
          poetry_sources.find { |source| source.name == name }
        end

        sig { params(key: String).returns(T::Array[String]) }
        def workspace_globs(key)
          tool = section(@data, "tool", "tool")
          uv = tool && section(tool, "uv", "tool.uv")
          workspace = uv && section(uv, "workspace", "tool.uv.workspace")
          value = workspace&.[](key)
          return [] if value.nil?

          PyprojectValueParser.string_array(value, "tool.uv.workspace.#{key}")
        end

        private

        sig do
          params(data: T.nilable(PyprojectValueParser::ObjectHash), context: String)
            .returns(T.nilable(ProjectMetadata))
        end
        def metadata_from(data, context)
          return unless data

          ProjectMetadata.new(
            name: PyprojectValueParser.optional_string(data["name"], "#{context}.name"),
            description: PyprojectValueParser.optional_string(data["description"], "#{context}.description")
          )
        end

        sig { returns(T.nilable(PyprojectValueParser::ObjectHash)) }
        def poetry_root
          tool = section(@data, "tool", "tool")
          tool && section(tool, "poetry", "tool.poetry")
        end

        sig { returns(T::Array[PoetrySource]) }
        def poetry_sources
          root = poetry_root
          return [] unless root

          value = root["source"]
          return [] if value.nil?

          PyprojectValueParser.array(value, "tool.poetry.source").map do |source|
            source = PyprojectValueParser.object_hash(source, "tool.poetry.source entry")
            PoetrySource.new(
              name: PyprojectValueParser.string(source["name"], "Poetry source name"),
              url: PyprojectValueParser.optional_string(source["url"], "Poetry source url")
            )
          end
        end

        sig do
          params(
            hash: PyprojectValueParser::ObjectHash,
            key: String,
            context: String
          ).returns(T.nilable(PyprojectValueParser::ObjectHash))
        end
        def section(hash, key, context)
          value = hash[key]
          return if value.nil?

          PyprojectValueParser.object_hash(value, context)
        end
      end
    end
  end
end
