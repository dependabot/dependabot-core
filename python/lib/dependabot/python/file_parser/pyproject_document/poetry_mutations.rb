# typed: strong
# frozen_string_literal: true

require "dependabot/python/file_parser/pyproject_document"
require "dependabot/python/file_parser/poetry_lock"
require "dependabot/python/name_normaliser"
require "dependabot/python/requirement"

module Dependabot
  module Python
    class FileParser < Dependabot::FileParsers::Base
      class PyprojectDocument
        class AuthSource
          extend T::Sig

          sig { params(data: Object).void }
          def initialize(data)
            @data = T.let(PyprojectValueParser.object_hash(data, "Poetry source"), PyprojectValueParser::ObjectHash)
          end

          sig { returns(T.nilable(String)) }
          def name
            PyprojectValueParser.optional_string(@data["name"], "Poetry source name")
          end

          sig { returns(T.nilable(String)) }
          def url
            PyprojectValueParser.optional_string(@data["url"], "Poetry source url")
          end
        end

        sig { returns(String) }
        def to_toml
          T.cast(TomlRB.dump(@data), String)
        end

        sig { returns(T::Array[AuthSource]) }
        def poetry_auth_sources
          value = poetry_root&.[]("source")
          return [] if value.nil?

          PyprojectValueParser.array(value, "tool.poetry.source").map { |entry| AuthSource.new(entry) }
        end

        sig { params(version: String).void }
        def update_python_requirement(version)
          root = mutable_poetry_root
          return unless root

          dependencies = mutable_section(root, "dependencies", "tool.poetry.dependencies")
          specification = dependencies&.[]("python")
          return unless specification

          constraint = PyprojectValueParser.string(specification, "tool.poetry.dependencies.python")
          requirements = Requirement.requirements_array(constraint)
          return if requirements.empty? || requirements.any? { |requirement| requirement.satisfied_by?(version) }

          dependencies["python"] = "~#{version}"
        end

        sig { params(name: String, requirement: String).void }
        def set_poetry_requirement(name:, requirement:)
          rewrite_poetry_requirement(name, requirement, preserve_enrichment: false)
        end

        sig { params(name: String, requirement: String).void }
        def pin_poetry_requirement(name:, requirement:)
          rewrite_poetry_requirement(name, requirement, preserve_enrichment: true)
        end

        sig { params(name: String, requirement: String, production: T::Boolean).void }
        def add_poetry_dependency(name:, requirement:, production:)
          root = mutable_poetry_root
          return unless root

          type = production ? "dependencies" : "dev-dependencies"
          table = T.must(mutable_section(root, type, "tool.poetry.#{type}", create: true))
          table[name] = requirement
        end

        sig { params(lock: PoetryLock, excluding: T::Array[String]).void }
        def freeze_poetry_dependencies(lock:, excluding:)
          root = mutable_poetry_root
          return unless root

          PyprojectFilesParser::POETRY_DEPENDENCY_TYPES.each do |type|
            next unless root[type]

            table = T.must(mutable_section(root, type, "tool.poetry.#{type}"))
            table.each_key do |name|
              normalized = NameNormaliser.normalise(name)
              next if excluding.include?(normalized)

              record = lock.record_for(normalized, &:itself)
              freeze_poetry_entry(table, name, record) if record
            end
          end
        end

        private

        sig do
          params(
            parent: PyprojectValueParser::ObjectHash, key: String, context: String, create: T::Boolean
          ).returns(T.nilable(PyprojectValueParser::ObjectHash))
        end
        def mutable_section(parent, key, context, create: false)
          value = parent[key]
          return if value.nil? && !create

          table = value.nil? ? {} : PyprojectValueParser.object_hash(value, context)
          parent[key] = table
          table
        end

        sig { returns(T.nilable(PyprojectValueParser::ObjectHash)) }
        def mutable_poetry_root
          tool = mutable_section(@data, "tool", "tool")
          tool && mutable_section(tool, "poetry", "tool.poetry")
        end

        sig do
          params(_block: T.proc.params(table: PyprojectValueParser::ObjectHash).void).void
        end
        def each_poetry_table(&_block)
          root = mutable_poetry_root
          return unless root

          PyprojectFilesParser::POETRY_DEPENDENCY_TYPES.each do |type|
            table = mutable_section(root, type, "tool.poetry.#{type}")
            yield(table) if table
          end
          groups = mutable_section(root, "group", "tool.poetry.group")
          groups&.each_key do |name|
            group = T.must(mutable_section(groups, name, "tool.poetry.group.#{name}"))
            table = mutable_section(group, "dependencies", "tool.poetry.group.#{name}.dependencies")
            yield(table) if table
          end
        end

        sig { params(name: String, requirement: String, preserve_enrichment: T::Boolean).void }
        def rewrite_poetry_requirement(name, requirement, preserve_enrichment:)
          each_poetry_table do |table|
            key = table.keys.find { |entry| NameNormaliser.normalise(entry) == name }
            next unless key

            value = table[key]
            if value.is_a?(Hash)
              entry = PyprojectValueParser.object_hash(value, "Poetry dependency #{key}")
              next if preserve_enrichment && !entry.key?("version")

              entry["version"] = requirement
              table[key] = entry
            else
              table[key] = requirement
            end
          end
        end

        sig { params(table: PyprojectValueParser::ObjectHash, name: String, record: PoetryLock::Record).void }
        def freeze_poetry_entry(table, name, record)
          version = record.version
          source_type = record.source_type
          return if %w(directory file url).include?(source_type)

          value = table[name]
          if source_type == "git"
            table[name] = frozen_git_declaration(value, name, record.git_source)
          elsif value.is_a?(Hash)
            entry = PyprojectValueParser.object_hash(value, "Poetry dependency #{name}")
            entry["version"] = version
            table[name] = entry
          elsif !value.is_a?(Array)
            table[name] = version
          end
        end

        sig do
          params(value: Object, name: String, source: PoetryLock::GitSource).returns(PyprojectValueParser::ObjectHash)
        end
        def frozen_git_declaration(value, name, source)
          declaration = T.let({ "git" => source.url, "rev" => source.reference }, PyprojectValueParser::ObjectHash)
          declaration["subdirectory"] = source.subdirectory if source.subdirectory
          if value.is_a?(Hash)
            extras = PyprojectValueParser.object_hash(value, "Poetry dependency #{name}")["extras"]
            if extras
              declaration["extras"] = PyprojectValueParser.string_array(extras, "Poetry dependency #{name} extras")
            end
          end
          declaration
        end
      end
    end
  end
end
