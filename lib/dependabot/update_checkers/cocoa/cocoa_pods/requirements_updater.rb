# frozen_string_literal: true
require "gemnasium/parser"
require "dependabot/update_checkers/base"

module Dependabot
  module UpdateCheckers
    module Cocoa
      class CocoaPods < Dependabot::UpdateCheckers::Base
        class RequirementsUpdater
          class UnfixableRequirement < StandardError; end

          attr_reader :requirements, :existing_version,
                      :latest_version, :latest_resolvable_version

          def initialize(requirements:, existing_version:,
                         latest_version:, latest_resolvable_version:)
            @requirements = requirements

            if existing_version
              @existing_version = Gem::Version.new(existing_version)
            end

            @latest_version = Gem::Version.new(latest_version) if latest_version

            return unless latest_resolvable_version
            @latest_resolvable_version =
              Gem::Version.new(latest_resolvable_version)
          end

          def updated_requirements
            requirements.map do |req|
              case req[:file]
              when "Podfile" then updated_podfile_requirement(req)
              else raise "Unexpected file name: #{req[:file]}"
              end
            end
          end

          private

          def updated_podfile_requirement(req)
            return req unless latest_resolvable_version

            original_req = Gem::Requirement.new(req[:requirement].split(","))

            if original_req.satisfied_by?(latest_resolvable_version) &&
               (existing_version.nil? ||
               latest_resolvable_version <= existing_version)
              return req
            end

            new_req = req[:requirement].gsub(/<=?/, "~>")
            new_req.sub!(Gemnasium::Parser::Patterns::VERSION) do |old_version|
              at_same_precision(latest_resolvable_version, old_version)
            end

            req.dup.merge(requirement: new_req)
          end

          def at_same_precision(new_version, old_version)
            precision = old_version.to_s.split(".").count
            new_version.to_s.split(".").first(precision).join(".")
          end
        end
      end
    end
  end
end
