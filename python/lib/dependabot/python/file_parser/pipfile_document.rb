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
      class PipfileDocument
        extend T::Sig

        class Entry
          extend T::Sig

          sig { params(name: String, value: Object, context: String).void }
          def initialize(name:, value:, context:)
            @name = name
            @context = context
            @value = T.let(
              value.is_a?(String) ? value : PyprojectValueParser.object_hash(value, context),
              T.any(String, PyprojectValueParser::ObjectHash)
            )
          end

          sig { returns(String) }
          attr_reader :name

          sig { returns(T::Boolean) }
          def specifies_version?
            value = @value
            return true if value.is_a?(String)

            version = value["version"]
            return false if version.nil? || version == false
            return true if version.is_a?(String) || version == true

            raise TypeError, "#{@context} version must be a string or boolean"
          end

          sig { returns(T::Boolean) }
          def git_or_path?
            value = @value
            value.is_a?(Hash) && (value.key?("git") || value.key?("path"))
          end

          sig { returns(String) }
          def requirement
            value = @value
            return value.empty? ? "*" : value if value.is_a?(String)

            PyprojectValueParser.string(value["version"], "#{@context} version")
          end

          sig { returns(T.nilable(String)) }
          def lookup_version
            value = @value
            return value.strip if value.is_a?(String)

            PyprojectValueParser.optional_string(value["version"], "#{@context} version")
          end

          sig { returns(T.nilable(String)) }
          def lockfile_version
            value = @value
            version = value.is_a?(String) ? value : value["version"]
            return unless version
            return if git_or_path?

            PyprojectValueParser.string(version, "#{@context} version")
          end
        end

        sig { params(file: Dependabot::DependencyFile).returns(PipfileDocument) }
        def self.from_file(file)
          new(data: T.cast(TomlRB.parse(T.must(file.content)), Object), context: file.path)
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          raise Dependabot::DependencyFileNotParseable, file.path
        end

        sig { params(data: Object, context: String).void }
        def initialize(data:, context:)
          @data = T.let(PyprojectValueParser.object_hash(data, context), PyprojectValueParser::ObjectHash)
          @context = context
        end

        sig { params(group: String).returns(T::Array[Entry]) }
        def entries(group)
          value = @data[group]
          return [] unless value
          return [] if value.is_a?(Array) && value.empty?

          context = "#{@context} #{group}"
          PyprojectValueParser.object_hash(value, context).map do |name, requirement|
            Entry.new(name: name, value: requirement, context: "#{context} entry")
          end
        end
      end
    end
  end
end
