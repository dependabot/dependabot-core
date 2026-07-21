# typed: strong
# frozen_string_literal: true

require "dependabot/file_parsers/base"
require "dependabot/swift/native_requirement"

module Dependabot
  module Swift
    class FileParser < Dependabot::FileParsers::Base
      class ManifestParser
        extend T::Sig
        extend T::Helpers

        DEPENDENCY =
          /(?<declaration>\.package\(\s*
            (?:name:\s+"[^"]+",\s*)?url:\s+"(?<url>[^"]+)",\s*(?<requirement>#{NativeRequirement::REGEXP})\s*
           \))/x

        sig do
          params(
            manifest: Dependabot::DependencyFile,
            requirement: Dependabot::DependencyRequirement
          ).void
        end
        def initialize(manifest, requirement:)
          @manifest = manifest
          @requirement = requirement
        end

        sig { returns(T::Array[T::Hash[Symbol, Object]]) }
        def requirements
          found = manifest.content&.scan(DEPENDENCY)&.find do |_declaration, url, _requirement|
            SharedHelpers.scp_to_standard(url.to_s) == source_url
          end

          return [] unless found

          declaration = T.cast(found, T::Array[String]).first
          requirement = NativeRequirement.new(T.must(T.cast(found, T::Array[String]).last))

          [
            {
              requirement: requirement.to_s,
              groups: ["dependencies"],
              file: manifest.name,
              source: T.must(self.requirement.source),
              metadata: { declaration_string: declaration, requirement_string: requirement.declaration }
            }
          ]
        end

        private

        sig { returns(Dependabot::DependencyFile) }
        attr_reader :manifest

        sig { returns(Dependabot::DependencyRequirement) }
        attr_reader :requirement

        sig { returns(String) }
        def source_url
          value = requirement.source_string(:url)
          raise TypeError, "Expected dependency source URL to be a String" unless value

          value
        end
      end
    end
  end
end
