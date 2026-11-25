# typed: strict
# frozen_string_literal: true

require "fileutils"
require "pathname"
require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/shared_helpers"
require "dependabot/python/language"
require "dependabot/python/native_helpers"

module Dependabot
  module Python
    class InvalidRequirementsFileParserResult < Dependabot::DependabotError; end

    class RequirementsFileParser
      extend T::Sig

      SCHEMA_VERSION = 1
      COMPONENT_STATUSES = %w(complete partial).freeze
      COMPONENT_REASONS = %w(remote_reference cycle local_path).freeze
      EDGE_TYPES = %w(requirement constraint).freeze
      ObjectHash = T.type_alias { T::Hash[String, Object] }
      REQUIREMENT_FILE_EVALUATION_ERRORS = %w(
        InstallationError RequirementsFileParseError InvalidMarker
        InvalidRequirement ValueError RecursionError
      ).freeze

      class SourceSpan < T::ImmutableStruct
        const :start_line, Integer
        const :end_line, Integer
      end

      class Declaration < T::ImmutableStruct
        const :name, String
        const :version, T.nilable(String), default: nil
        const :markers, T.nilable(String), default: nil
        const :file, String
        const :requirement, T.nilable(String), default: nil
        const :source_requirement, String
        const :extras, T::Array[String]
        const :constraint, T::Boolean
        const :editable, T::Boolean
        const :local, T::Boolean
        const :hashes, T::Array[String]
        const :source, SourceSpan
      end

      class FileNode < T::ImmutableStruct
        const :path, String
        const :component_id, String
      end

      class Edge < T::ImmutableStruct
        const :from, String
        const :to, String
        const :type, String
        const :remote, T::Boolean
        const :source, SourceSpan
      end

      class Component < T::ImmutableStruct
        extend T::Sig

        const :id, String
        const :files, T::Array[String]
        const :roots, T::Array[String]
        const :status, String
        const :reasons, T::Array[String]
        const :has_index_options, T::Boolean

        sig { returns(T::Boolean) }
        def complete?
          status == "complete"
        end
      end

      class Result < T::ImmutableStruct
        extend T::Sig

        const :schema_version, Integer
        const :declarations, T::Array[Declaration]
        const :files, T::Array[FileNode]
        const :edges, T::Array[Edge]
        const :roots, T::Array[String]
        const :components, T::Array[Component]

        sig { params(path: String, edge_types: T::Array[String]).returns(T::Array[String]) }
        def local_paths_from(path, edge_types: EDGE_TYPES)
          edges.filter_map do |edge|
            edge.to if !edge.remote && edge.from == path && edge_types.include?(edge.type)
          end
        end

        sig do
          params(
            paths: T::Array[String],
            edge_types: T::Array[String]
          ).returns(T::Array[String])
        end
        def reachable_local_files(paths, edge_types: EDGE_TYPES)
          reached = T.let(Set.new(paths), T::Set[String])
          pending = paths.dup

          until pending.empty?
            path = T.must(pending.shift)
            local_paths_from(path, edge_types: edge_types).each do |target|
              pending << target if reached.add?(target)
            end
          end

          reached.to_a
        end
      end

      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile],
          requirement_files: T.nilable(T::Array[String])
        ).void
      end
      def initialize(dependency_files:, requirement_files: nil)
        @dependency_files = dependency_files
        @requirement_files = requirement_files
      end

      sig { returns(Result) }
      def parse
        SharedHelpers.in_a_temporary_directory do
          write_dependency_files
          raw_result = SharedHelpers.run_helper_subprocess(
            command: "pyenv exec python3 #{NativeHelpers.python_helper_path}",
            function: "parse_requirements_v2",
            args: @requirement_files.nil? ? [Dir.pwd] : [Dir.pwd, @requirement_files],
            env: { "PYENV_VERSION" => Language::PRE_INSTALLED_HIGHEST_VERSION.to_s }
          )
          self.class.from_helper_result(raw_result)
        end
      rescue SharedHelpers::HelperSubprocessFailed => e
        raise unless e.message.start_with?(*REQUIREMENT_FILE_EVALUATION_ERRORS)

        raise Dependabot::DependencyFileNotEvaluatable, e.message
      end

      sig { params(result: Object).returns(Result) }
      def self.from_helper_result(result)
        result_hash = object_hash(result, "parse_requirements result")
        schema_version = integer(result_hash["schema_version"], "parse_requirements schema_version")
        unless schema_version == SCHEMA_VERSION
          raise InvalidRequirementsFileParserResult,
                "Unsupported parse_requirements schema_version #{schema_version.inspect}; expected #{SCHEMA_VERSION}"
        end

        parsed = build_result(result_hash, schema_version)
        validate_graph(parsed)
        parsed
      rescue TypeError => e
        raise InvalidRequirementsFileParserResult, e.message
      end

      class << self
        extend T::Sig

        private

        sig { params(value: Object, context: String).returns(ObjectHash) }
        def object_hash(value, context)
          raise TypeError, "#{context} must be an object" unless value.is_a?(Hash)

          value.each_with_object(T.let({}, ObjectHash)) do |(key, item), result|
            raise TypeError, "#{context} keys must be strings" unless key.is_a?(String)

            result[key] = T.cast(item, Object)
          end
        end

        sig { params(value: Object, context: String).returns(T::Array[Object]) }
        def array(value, context)
          raise TypeError, "#{context} must be an array" unless value.is_a?(Array)

          value.map { |item| T.cast(item, Object) }
        end

        sig { params(result_hash: ObjectHash, schema_version: Integer).returns(Result) }
        def build_result(result_hash, schema_version)
          declarations = array(result_hash["declarations"], "parse_requirements declarations")
                         .each_with_index.map { |item, index| declaration(item, index) }
          files = array(result_hash["files"], "parse_requirements files")
                  .each_with_index.map { |item, index| file_node(item, index) }
          edges = array(result_hash["edges"], "parse_requirements edges")
                  .each_with_index.map { |item, index| edge(item, index) }
          components = array(result_hash["components"], "parse_requirements components")
                       .each_with_index.map { |item, index| component(item, index) }

          Result.new(
            schema_version: schema_version,
            declarations: declarations,
            files: files,
            edges: edges,
            roots: string_array(result_hash["roots"], "parse_requirements roots"),
            components: components
          )
        end

        sig { params(value: Object, context: String).returns(String) }
        def string(value, context)
          return value if value.is_a?(String)

          raise TypeError, "#{context} must be a string"
        end

        sig { params(value: T.nilable(Object), context: String).returns(T.nilable(String)) }
        def optional_string(value, context)
          return if value.nil?

          string(value, context)
        end

        sig { params(value: Object, context: String).returns(Integer) }
        def integer(value, context)
          return value if value.is_a?(Integer)

          raise TypeError, "#{context} must be an integer"
        end

        sig { params(value: Object, context: String).returns(T::Boolean) }
        def boolean(value, context)
          return true if value == true
          return false if value == false

          raise TypeError, "#{context} must be a boolean"
        end

        sig { params(value: Object, context: String).returns(T::Array[String]) }
        def string_array(value, context)
          array(value, context).map { |item| string(item, "#{context} item") }
        end

        sig { params(value: Object, context: String).returns(SourceSpan) }
        def source_span(value, context)
          hash = object_hash(value, context)
          start_line = integer(hash["start_line"], "#{context} start_line")
          end_line = integer(hash["end_line"], "#{context} end_line")
          unless start_line.positive? && end_line >= start_line
            raise TypeError, "#{context} must be a valid positive line range"
          end

          SourceSpan.new(start_line: start_line, end_line: end_line)
        end

        sig { params(value: Object, index: Integer).returns(Declaration) }
        def declaration(value, index)
          context = "parse_requirements declarations[#{index}]"
          hash = object_hash(value, context)
          Declaration.new(
            name: string(hash["name"], "#{context} name"),
            version: optional_string(hash["version"], "#{context} version"),
            markers: optional_string(hash["markers"], "#{context} markers"),
            file: string(hash["file"], "#{context} file"),
            requirement: optional_string(hash["requirement"], "#{context} requirement"),
            source_requirement: string(hash["source_requirement"], "#{context} source_requirement"),
            extras: string_array(hash["extras"], "#{context} extras"),
            constraint: boolean(hash["constraint"], "#{context} constraint"),
            editable: boolean(hash["editable"], "#{context} editable"),
            local: boolean(hash["local"], "#{context} local"),
            hashes: string_array(hash["hashes"], "#{context} hashes"),
            source: source_span(hash["source"], "#{context} source")
          )
        end

        sig { params(value: Object, index: Integer).returns(FileNode) }
        def file_node(value, index)
          context = "parse_requirements files[#{index}]"
          hash = object_hash(value, context)
          FileNode.new(
            path: string(hash["path"], "#{context} path"),
            component_id: string(hash["component_id"], "#{context} component_id")
          )
        end

        sig { params(value: Object, index: Integer).returns(Edge) }
        def edge(value, index)
          context = "parse_requirements edges[#{index}]"
          hash = object_hash(value, context)
          edge_type = string(hash["type"], "#{context} type")
          unless EDGE_TYPES.include?(edge_type)
            raise TypeError, "#{context} type must be one of #{EDGE_TYPES.join(', ')}"
          end

          Edge.new(
            from: string(hash["from"], "#{context} from"),
            to: string(hash["to"], "#{context} to"),
            type: edge_type,
            remote: boolean(hash["remote"], "#{context} remote"),
            source: source_span(hash["source"], "#{context} source")
          )
        end

        sig { params(value: Object, index: Integer).returns(Component) }
        def component(value, index)
          context = "parse_requirements components[#{index}]"
          hash = object_hash(value, context)
          status = string(hash["status"], "#{context} status")
          unless COMPONENT_STATUSES.include?(status)
            raise TypeError, "#{context} status must be one of #{COMPONENT_STATUSES.join(', ')}"
          end

          reasons = string_array(hash["reasons"], "#{context} reasons")
          unknown_reasons = reasons - COMPONENT_REASONS
          raise TypeError, "#{context} has unknown reasons: #{unknown_reasons.join(', ')}" if unknown_reasons.any?

          Component.new(
            id: string(hash["id"], "#{context} id"),
            files: string_array(hash["files"], "#{context} files"),
            roots: string_array(hash["roots"], "#{context} roots"),
            status: status,
            reasons: reasons,
            has_index_options: boolean(hash["has_index_options"], "#{context} has_index_options")
          )
        end

        sig { params(result: Result).void }
        def validate_graph(result)
          validate_unique_graph_records(result)
          validate_component_files(result)
          validate_roots(result)
          validate_declarations(result)
          validate_edges(result)
        end

        sig { params(result: Result).void }
        def validate_unique_graph_records(result)
          component_ids = result.components.map(&:id)
          raise TypeError, "parse_requirements component ids must be unique" unless component_ids.uniq == component_ids

          files = result.files.map(&:path)
          raise TypeError, "parse_requirements file paths must be unique" unless files.uniq == files
        end

        sig { params(result: Result).void }
        def validate_component_files(result)
          files = result.files.map(&:path)
          component_files = result.components.flat_map(&:files)
          unless component_files.sort == files.sort
            raise TypeError, "parse_requirements components must contain every file exactly once"
          end

          component_by_file = result.components.each_with_object({}) do |component, mapping|
            component.files.each { |file| mapping[file] = component.id }
          end
          result.files.each do |file|
            next if component_by_file[file.path] == file.component_id

            raise TypeError, "parse_requirements file #{file.path} has an unknown component"
          end
        end

        sig { params(result: Result).void }
        def validate_roots(result)
          result.components.each do |component|
            unless component.roots.all? { |root| component.files.include?(root) }
              raise TypeError, "parse_requirements component #{component.id} has a root outside the component"
            end
            next if (component.complete? && component.reasons.empty?) ||
                    (!component.complete? && component.reasons.any?)

            raise TypeError, "parse_requirements component #{component.id} has inconsistent status and reasons"
          end

          return if result.roots.sort == result.components.flat_map(&:roots).uniq.sort

          raise TypeError, "parse_requirements roots must match component roots"
        end

        sig { params(result: Result).void }
        def validate_declarations(result)
          files = result.files.map(&:path)
          result.declarations.each do |declaration|
            next if files.include?(declaration.file)

            raise TypeError, "parse_requirements declaration has an unknown file"
          end
        end

        sig { params(result: Result).void }
        def validate_edges(result)
          files = result.files.map(&:path)
          result.edges.each do |edge|
            raise TypeError, "parse_requirements edge has an unknown source file" unless files.include?(edge.from)
            next if edge.remote || files.include?(edge.to)

            raise TypeError, "parse_requirements local edge has an unknown target file"
          end
        end
      end

      private

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      attr_reader :dependency_files

      sig { void }
      def write_dependency_files
        dependency_files.each do |file|
          next if file.name == ".python-version"

          content = file.content
          next if content.nil?

          FileUtils.mkdir_p(Pathname.new(file.name).dirname)
          File.write(file.name, content)
        end
      end
    end
  end
end
