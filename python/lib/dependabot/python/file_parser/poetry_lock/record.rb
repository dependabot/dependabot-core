# typed: strong
# frozen_string_literal: true

require "dependabot/python/file_parser/poetry_lock"

module Dependabot
  module Python
    class FileParser < Dependabot::FileParsers::Base
      class PoetryLock
        class GitSource < T::ImmutableStruct
          const :url, String
          const :reference, String
          const :subdirectory, T.nilable(String), default: nil
        end

        class Scope < T::ImmutableStruct
          extend T::Sig

          const :optional, T::Boolean
          const :groups, T::Array[String]
          const :markers, T::Hash[String, T::Array[String]]

          sig { params(group: String).returns(T::Array[String]) }
          def markers_for(group)
            markers.fetch(group, [])
          end
        end

        class Record
          extend T::Sig

          sig { params(data: Object).void }
          def initialize(data)
            @data = data
            @object = T.let(nil, T.nilable(PyprojectValueParser::ObjectHash))
          end

          sig { returns(Package) }
          def to_package
            Package.new(
              name: PyprojectValueParser.string(object["name"], "Poetry lock package name"),
              version: version,
              source_type: source_type
            )
          end

          sig { returns(T.nilable(String)) }
          def name
            PyprojectValueParser.optional_string(object["name"], "Poetry lock package name")
          end

          sig { returns(String) }
          def version
            PyprojectValueParser.string(object["version"], "Poetry lock package version")
          end

          sig { returns(T.nilable(String)) }
          def source_type
            PyprojectValueParser.optional_string(source&.[]("type"), "Poetry lock package source type")
          end

          sig { returns(GitSource) }
          def git_source
            fields = source || {}
            GitSource.new(
              url: PyprojectValueParser.string(fields["url"], "Poetry lock package source url"),
              reference: PyprojectValueParser.string(fields["reference"], "Poetry lock package source reference"),
              subdirectory: PyprojectValueParser.optional_string(
                fields["subdirectory"], "Poetry lock package source subdirectory"
              )
            )
          end

          sig { returns(Scope) }
          def scope
            groups_value = object["groups"]
            groups = if groups_value.nil?
                       []
                     elsif groups_value.is_a?(String)
                       [groups_value]
                     else
                       PyprojectValueParser.string_array(groups_value, "Poetry lock package groups")
                     end
            groups = ["main"] if groups.empty?

            optional = object["optional"]
            unless optional.nil? || optional == true || optional == false
              raise TypeError, "Poetry lock package optional must be a boolean"
            end

            Scope.new(optional: optional == true, groups: groups, markers: markers_for(groups))
          end

          private

          sig { returns(PyprojectValueParser::ObjectHash) }
          def object
            @object ||= PyprojectValueParser.object_hash(@data, "Poetry lock package")
          end

          sig { returns(T.nilable(PyprojectValueParser::ObjectHash)) }
          def source
            value = object["source"]
            PyprojectValueParser.object_hash(value, "Poetry lock package source") unless value.nil?
          end

          sig { params(groups: T::Array[String]).returns(T::Hash[String, T::Array[String]]) }
          def markers_for(groups)
            value = object["markers"]
            if value.is_a?(Hash)
              PyprojectValueParser.object_hash(value, "Poetry lock package markers").to_h do |group, marker|
                parsed = PyprojectValueParser.string(marker, "Poetry lock package markers.#{group}")
                [group, ["(#{parsed})"]]
              end
            else
              marker = PyprojectValueParser.optional_string(value, "Poetry lock package markers")
              groups.to_h { |group| [group, marker ? ["(#{marker})"] : []] }
            end
          end
        end
      end
    end
  end
end
