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

        private

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
