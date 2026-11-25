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
      class PoetryLock
        extend T::Sig

        require_relative "poetry_lock/record"

        class Package < T::ImmutableStruct
          extend T::Sig

          const :name, String
          const :version, String
          const :source_type, T.nilable(String), default: nil

          sig { params(value: Object).returns(Package) }
          def self.from_object(value)
            Record.new(value).to_package
          end

          sig { returns(T::Hash[Symbol, T.nilable(String)]) }
          def to_h
            {
              name: name,
              version: version,
              source_type: source_type
            }
          end
        end

        sig { params(data: PyprojectValueParser::ObjectHash).void }
        def initialize(data)
          @data = data
          @packages = T.let(nil, T.nilable(T::Array[Package]))
          @records = T.let(nil, T.nilable(T::Array[Record]))
        end

        sig { params(file: Dependabot::DependencyFile).returns(PoetryLock) }
        def self.from_file(file)
          document = from_content(T.must(file.content))
          document.packages
          document
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          raise Dependabot::DependencyFileNotParseable, file.path
        end

        sig { params(content: String).returns(PoetryLock) }
        def self.from_content(content)
          parsed = T.cast(TomlRB.parse(content), Object)
          new(PyprojectValueParser.object_hash(parsed, "poetry.lock"))
        end

        sig { returns(T::Array[Package]) }
        def packages
          @packages ||= records.map(&:to_package)
        end

        sig do
          params(name: String, _normalizer: T.proc.params(name: String).returns(String)).returns(T.nilable(Record))
        end
        def record_for(name, &_normalizer)
          records.find do |record|
            record_name = record.name
            record_name && yield(record_name) == name
          end
        end

        sig do
          params(name: String, _normalizer: T.proc.params(name: String).returns(String)).returns(T::Array[Record])
        end
        def records_for(name, &_normalizer)
          records.select do |record|
            record_name = record.name
            record_name && yield(record_name) == name
          end
        end

        sig do
          params(
            name: String,
            normalizer: T.proc.params(name: String).returns(String)
          )
            .returns(T.nilable(String))
        end
        def version_for(name, &normalizer)
          record_for(yield(name), &normalizer)&.version
        end

        sig { returns(String) }
        def python_versions
          PyprojectValueParser.string(metadata["python-versions"], "poetry.lock metadata.python-versions")
        end

        sig { returns(String) }
        def content_hash
          PyprojectValueParser.string(metadata["content-hash"], "poetry.lock metadata.content-hash")
        end

        private

        sig { returns(T::Array[Record]) }
        def records
          @records ||= if @data["package"].nil?
                         []
                       else
                         PyprojectValueParser.array(@data["package"], "poetry.lock package").map do |entry|
                           Record.new(entry)
                         end
                       end
        end

        sig { returns(PyprojectValueParser::ObjectHash) }
        def metadata
          PyprojectValueParser.object_hash(@data["metadata"], "poetry.lock metadata")
        end
      end
    end
  end
end
