# typed: strong
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/errors"
require "dependabot/python/file_parser"
require "dependabot/python/file_parser/pipfile_document"

module Dependabot
  module Python
    class FileParser < Dependabot::FileParsers::Base
      class PipfileLockDocument
        extend T::Sig

        class PreservedMetadata < T::ImmutableStruct
          const :requires, Object
          const :sources, Object
        end

        sig { params(file: Dependabot::DependencyFile).returns(PipfileLockDocument) }
        def self.from_file(file)
          new(data: T.cast(JSON.parse(T.must(file.content)), Object), context: file.path)
        rescue JSON::ParserError
          raise Dependabot::DependencyFileNotParseable, file.path
        end

        sig { params(data: Object, context: String).void }
        def initialize(data:, context:)
          @data = T.let(PyprojectValueParser.object_hash(data, context), PyprojectValueParser::ObjectHash)
          @context = context
        end

        sig { params(group: String).returns(T::Array[PipfileDocument::Entry]) }
        def entries(group)
          entries = section(group)
          return [] unless entries

          entries.filter_map do |name, value|
            next unless value.is_a?(String) || value.is_a?(Hash)

            PipfileDocument::Entry.new(name: name, value: value, context: "#{@context} #{group} entry")
          end
        end

        sig { params(group: String, name: String).returns(T.nilable(String)) }
        def version_for(group, name)
          value = section(group)&.[](name)
          return if value.nil? || value.is_a?(Array)

          unless value.is_a?(String) || value.is_a?(Hash)
            raise TypeError, "#{@context} #{group} entry must be a string, object, or array"
          end

          PipfileDocument::Entry.new(name: name, value: value, context: "#{@context} #{group} entry").lookup_version
        end

        sig { params(group: String).returns(T::Array[String]) }
        def dependency_names(group)
          value = @data[group]
          value.nil? ? [] : object_value(value, group).keys
        end

        sig { returns(PreservedMetadata) }
        def preserved_metadata
          fields = metadata
          PreservedMetadata.new(requires: fields["requires"], sources: fields["sources"])
        end

        sig { params(metadata: PreservedMetadata, checksum: String).returns(String) }
        def restored_content(metadata:, checksum:)
          fields = self.metadata
          hash = object_value(fields["hash"], "_meta.hash")
          hash["sha256"] = checksum
          fields["hash"] = hash
          fields["requires"] = metadata.requires
          fields["sources"] = metadata.sources

          JSON.pretty_generate(@data.merge("_meta" => fields), indent: "    ")
              .gsub(/\{\n\s*\}/, "{}")
              .gsub(/\}\z/, "}\n")
        end

        private

        sig { returns(PyprojectValueParser::ObjectHash) }
        def metadata
          object_value(@data["_meta"], "_meta")
        end

        sig { params(value: Object, field: String).returns(PyprojectValueParser::ObjectHash) }
        def object_value(value, field)
          PyprojectValueParser.object_hash(value, "#{@context} #{field}")
        rescue TypeError => e
          raise Dependabot::DependencyFileNotParseable.new(@context, e.message)
        end

        sig { params(group: String).returns(T.nilable(PyprojectValueParser::ObjectHash)) }
        def section(group)
          value = @data[group]
          return unless value.is_a?(Hash)

          PyprojectValueParser.object_hash(value, "#{@context} #{group}")
        end
      end
    end
  end
end
