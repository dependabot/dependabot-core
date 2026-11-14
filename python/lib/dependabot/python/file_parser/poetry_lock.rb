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

        class Package < T::ImmutableStruct
          extend T::Sig

          # Packages from these sources are not on a package index, so they do not get a PyPI identity.
          NON_INDEX_SOURCE_TYPES = %w(directory file git url).freeze

          const :name, String
          const :version, String
          const :source_type, T.nilable(String), default: nil
          const :dependency_names, T::Array[String], default: []

          sig { params(value: Object).returns(Package) }
          def self.from_object(value)
            hash = PyprojectValueParser.object_hash(value, "Poetry lock package")
            source = hash["source"]
            source_hash =
              if source.nil?
                nil
              else
                PyprojectValueParser.object_hash(source, "Poetry lock package source")
              end

            new(
              name: PyprojectValueParser.string(hash["name"], "Poetry lock package name"),
              version: PyprojectValueParser.string(hash["version"], "Poetry lock package version"),
              source_type: PyprojectValueParser.optional_string(
                source_hash&.[]("type"),
                "Poetry lock package source type"
              ),
              dependency_names: dependency_names_from(hash["dependencies"])
            )
          end

          sig { params(value: T.nilable(Object)).returns(T::Array[String]) }
          def self.dependency_names_from(value)
            return [] unless value.is_a?(Hash)

            value.keys.grep(String)
          end

          sig { returns(T::Hash[Symbol, T.nilable(T.any(String, T::Array[String]))]) }
          def to_h
            {
              name: name,
              version: version,
              source_type: source_type,
              dependency_names: dependency_names
            }
          end

          sig { returns(T::Boolean) }
          def from_index?
            !NON_INDEX_SOURCE_TYPES.include?(source_type)
          end
        end

        sig { returns(T::Array[Package]) }
        attr_reader :packages

        sig { params(packages: T::Array[Package]).void }
        def initialize(packages)
          @packages = packages
        end

        sig { params(file: Dependabot::DependencyFile).returns(PoetryLock) }
        def self.from_file(file)
          parsed = T.cast(TomlRB.parse(T.must(file.content)), Object)
          document = PyprojectValueParser.object_hash(parsed, "poetry.lock")
          value = document["package"]
          packages =
            if value.nil?
              []
            else
              PyprojectValueParser.array(value, "poetry.lock package").map do |package|
                Package.from_object(package)
              end
            end
          new(packages)
        rescue TomlRB::ParseError, TomlRB::ValueOverwriteError
          raise Dependabot::DependencyFileNotParseable, file.path
        end

        sig do
          params(
            name: String,
            _normalizer: T.proc.params(name: String).returns(String)
          )
            .returns(T.nilable(String))
        end
        def version_for(name, &_normalizer)
          normalized_name = yield(name)
          packages.find { |package| yield(package.name) == normalized_name }&.version
        end
      end
    end
  end
end
