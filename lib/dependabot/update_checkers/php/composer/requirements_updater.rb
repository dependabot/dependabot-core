# frozen_string_literal: true

################################################################################
# For more details on Composer version constraints, see:                       #
# https://getcomposer.org/doc/articles/versions.md#writing-version-constraints #
################################################################################

require "dependabot/update_checkers/php/composer"

module Dependabot
  module UpdateCheckers
    module Php
      class Composer
        class RequirementsUpdater
          VERSION_REGEX = /[0-9]+(?:\.[a-zA-Z0-9*]+)*/

          def initialize(requirements:, library:,
                         latest_version:, latest_resolvable_version:)
            @requirements = requirements

            @latest_version = Gem::Version.new(latest_version) if latest_version

            @library = library

            return unless latest_resolvable_version
            @latest_resolvable_version =
              Gem::Version.new(latest_resolvable_version)
          end

          def updated_requirements
            return requirements unless latest_resolvable_version

            requirements.map do |req|
              if library?
                updated_library_requirement(req)
              else
                updated_app_requirement(req)
              end
            end
          end

          private

          attr_reader :requirements, :latest_version, :latest_resolvable_version

          def library?
            @library
          end

          def updated_app_requirement(req)
            current_requirement = req[:requirement]

            updated_requirement =
              current_requirement.
              sub(VERSION_REGEX) do |old_version|
                unless old_version.include?("*")
                  next latest_resolvable_version.to_s
                end

                old_parts = old_version.split(".")
                new_parts = latest_resolvable_version.to_s.split(".").
                            first(old_parts.count)
                new_parts.map.with_index do |part, i|
                  old_parts[i] == "*" ? "*" : part
                end.join(".")
              end

            req.merge(requirement: updated_requirement)
          end

          def updated_library_requirement(req)
            current_requirement = req[:requirement]
            return req if current_requirement.strip.split(" ").count > 1

            ruby_req = ruby_requirement(current_requirement)
            return req if ruby_req.satisfied_by?(latest_resolvable_version)

            updated_requirement =
              current_requirement.
              sub(VERSION_REGEX) do |old_version|
                unless old_version.include?("*")
                  next latest_resolvable_version.to_s
                end

                old_parts = old_version.split(".")
                new_parts = latest_resolvable_version.to_s.split(".").
                            first(old_parts.count)
                new_parts.map.with_index do |part, i|
                  old_parts[i] == "*" ? "*" : part
                end.join(".")
              end

            req.merge(requirement: updated_requirement)
          end

          def ruby_requirement(requirement_string)
            requirement_string = requirement_string.strip

            if requirement_string.include?("*")
              ruby_tilde_range(requirement_string.gsub(/(?:\.|^)\*/, ""))
            elsif requirement_string.start_with?("~")
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
