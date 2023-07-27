# frozen_string_literal: true

require "dependabot/file_parsers/base"
require "dependabot/swift/native_requirement"

module Dependabot
  module Swift
    class FileParser < Dependabot::FileParsers::Base
      class ManifestParser
        DEPENDENCY = /(?<declaration>\.package\(\s*(?:name: "[^"]+",\s*)?url: "(?<url>[^"]+)",\s*(?<requirement>.*)\))/

        def initialize(manifest, source:)
          @manifest = manifest
          @source = source
        end

        def requirements
          found = manifest.content.scan(DEPENDENCY).find do |_declaration, url, requirement|
            # TODO: Support pinning to specific revisions
            next if requirement.start_with?("branch:", ".branch(", "revision:", ".revision(")

            url == source[:url]
          end

          return [] unless found

          declaration = found.first
          requirement = NativeRequirement.new(found.last)

          [
            {
              requirement: requirement.to_s,
              groups: ["dependencies"],
              file: manifest.name,
              source: source,
              metadata: { declaration_string: declaration, requirement_string: requirement.declaration }
            }
          ]
        end

        private

        attr_reader :manifest, :source
      end
    end
  end
end
