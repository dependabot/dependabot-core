# frozen_string_literal: true

require "dependabot/update_checkers/java_script/npm_and_yarn"

module Dependabot
  module UpdateCheckers
    module JavaScript
      class NpmAndYarn
        class RequirementsUpdater
          VERSION_REGEX = /[0-9]+(?:\.[A-Za-z0-9\-_]+)*/

          attr_reader :requirements, :existing_version,
                      :latest_version, :latest_resolvable_version

          def initialize(requirements:, existing_version:,
                         latest_version:, latest_resolvable_version:)
            @requirements = requirements

            @latest_version = Gem::Version.new(latest_version) if latest_version

            if existing_version
              @existing_version = Gem::Version.new(existing_version)
            end

            return unless latest_resolvable_version
            @latest_resolvable_version =
              Gem::Version.new(latest_resolvable_version)
          end

          def updated_requirements
            return requirements unless latest_resolvable_version

            requirements.map do |req|
              if existing_version
                updated_app_requirement(req)
              else
                updated_library_requirement(req)
              end
            end
          end

          private

          def updated_app_requirement(req)
            current_requirement = req[:requirement]

            updated_requirement =
              current_requirement.
              sub(VERSION_REGEX) do |old_version|
                old_parts = old_version.split(".")
                new_parts = latest_resolvable_version.to_s.split(".").
                            first(old_parts.count)
                new_parts.map.with_index do |part, i|
                  old_parts[i].match?(/^x\b/) ? "x" : part
                end.join(".")
              end

            req.merge(requirement: updated_requirement)
          end

          def updated_library_requirement(req)
            current_requirement = req[:requirement]
            return req if current_requirement.strip.split(" ").count > 1
            return req if current_requirement.strip == ""

            ruby_req = ruby_requirement(current_requirement)
            return req if ruby_req.satisfied_by?(latest_resolvable_version)

            updated_requirement =
              current_requirement.
              sub(VERSION_REGEX) do |old_version|
                old_parts = old_version.split(".")
                new_parts = latest_resolvable_version.to_s.split(".").
                            first(old_parts.count)
                new_parts.map.with_index do |part, i|
                  old_parts[i].match?(/^x\b/) ? "x" : part
                end.join(".")
              end

            req.merge(requirement: updated_requirement)
          end

          def ruby_requirement(requirement_string)
            requirement_string = requirement_string.strip
            requirement_string = requirement_string.gsub(/(?:\.|^)[xX*]/, "")

            if requirement_string.start_with?("~")
              ruby_tilde_range(requirement_string)
            elsif requirement_string.start_with?("^")
              ruby_caret_range(requirement_string)
            else
              ruby_range(requirement_string)
            end
          end

          def ruby_hyphen_range(req_string)
            lower_bound, upper_bound = req_string.split("-")
            Gem::Requirement.new(">= #{lower_bound}", "<= #{upper_bound}")
          end

          def ruby_tilde_range(req_string)
            version = req_string.gsub(/^~/, "")
            parts = version.split(".")
            parts << "0" if parts.count < 3
            Gem::Requirement.new("~> #{parts.join('.')}")
          end

          def ruby_range(req_string)
            parts = req_string.split(".")
            parts << "0" if parts.count < 3
            Gem::Requirement.new("~> #{parts.join('.')}")
          end

          def ruby_caret_range(req_string)
            version = req_string.gsub(/^\^/, "")
            parts = version.split(".")
            first_non_zero = parts.find { |d| d != "0" }
            first_non_zero_index =
              first_non_zero ? parts.index(first_non_zero) : parts.count - 1
            upper_bound = parts.map.with_index do |part, i|
              if i < first_non_zero_index then part
              elsif i == first_non_zero_index then (part.to_i + 1).to_s
              else 0
              end
            end.join(".")

            Gem::Requirement.new(">= #{version}", "< #{upper_bound}")
          end
        end
      end
    end
  end
end
