# frozen_string_literal: true

require "dependabot/file_updaters/cocoa/cocoapods.rb"

module Dependabot
  module FileUpdaters
    module Cocoa
      class CocoaPods
        class PodfileUpdater
          def initialize(dependencies:, podfile:)
            @dependencies = dependencies
            @podfile = podfile
          end

          def updated_podfile_content
            dependencies.select { |dep| requirement_changed?(podfile, dep) }.
              reduce(podfile.content.dup) do |_content, dep|
              podfile.content.to_enum(:scan, POD_CALL).
                find { Regexp.last_match[:name] == dep.name }

              original_pod_declaration_string = Regexp.last_match.to_s
              updated_pod_declaration_string = update_pod_declaration_string(
                original_pod_declaration_string, dep
              )

              @updated_podfile_content = podfile.content.gsub(
                original_pod_declaration_string,
                updated_pod_declaration_string
              )
            end
          end

          private

          attr_reader :dependencies, :podfile

          def update_pod_declaration_string(original_string, dep)
            original_string.
              sub(Gemnasium::Parser::Patterns::REQUIREMENTS) do |old_reqs|
              old_version = old_reqs.
                            match(Gemnasium::Parser::Patterns::VERSION)[0]

              precision = old_version.split(".").count
              new_version = dep.version.split(".").first(precision).join(".")

              old_reqs.sub(old_version, new_version)
            end
          end

          def requirement_changed?(file, dependency)
            changed_requirements =
              dependency.requirements - dependency.previous_requirements

            changed_requirements.any? { |f| f[:file] == file.name }
          end
        end
      end
    end
  end
end
