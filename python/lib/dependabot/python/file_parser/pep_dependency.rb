# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/python/file_parser"

module Dependabot
  module Python
    class FileParser < Dependabot::FileParsers::Base
      class PepDependency < T::ImmutableStruct
        extend T::Sig

        const :name, String
        const :version, T.nilable(String), default: nil
        const :markers, T.nilable(String), default: nil
        const :file, String
        const :requirement, T.nilable(String), default: nil
        const :source_requirement, T.nilable(String), default: nil
        const :extras, T::Array[String]
        const :requirement_type, T.nilable(String), default: nil

        sig { params(result: Object).returns(T::Array[PepDependency]) }
        def self.from_helper_result(result)
          PyprojectValueParser.array(result, "PEP dependency result").map do |value|
            from_object(value)
          end
        end

        sig { params(value: Object).returns(PepDependency) }
        def self.from_object(value)
          hash = PyprojectValueParser.object_hash(value, "PEP dependency")
          new(
            name: PyprojectValueParser.string(hash["name"], "PEP dependency name"),
            version: PyprojectValueParser.optional_string(hash["version"], "PEP dependency version"),
            markers: PyprojectValueParser.optional_string(hash["markers"], "PEP dependency markers"),
            file: PyprojectValueParser.string(hash["file"], "PEP dependency file"),
            requirement: PyprojectValueParser.optional_string(hash["requirement"], "PEP dependency requirement"),
            source_requirement: PyprojectValueParser.optional_string(
              hash["source_requirement"],
              "PEP dependency source_requirement"
            ),
            extras: PyprojectValueParser.string_array(hash["extras"], "PEP dependency extras"),
            requirement_type: PyprojectValueParser.optional_string(
              hash["requirement_type"],
              "PEP dependency requirement_type"
            )
          )
        end
      end
    end
  end
end
