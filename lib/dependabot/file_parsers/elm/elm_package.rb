# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/file_fetchers/elm/elm_package"
require "dependabot/shared_helpers"
require "dependabot/utils/elm/version"

module Dependabot
  module FileParsers
    module Elm
      class ElmPackage < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/base/dependency_set"

        MAX_VERSION = 9999
        REQUIREMENT_REGEX =
          /(?<operator><=?)\s*(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$/

        def parse
          dependency_set = DependencySet.new

          parsed_package_file.fetch("dependencies").each do |name, req|
            dependency_set <<
              Dependency.new(
                name: name,
                version: max_version_for(req),
                requirements: [{
                  requirement: req, # 4.0 <= v <= 4.0
                  groups: nil, # we don't have this (its dev vs non-dev)
                  source: nil, # elm-package only has elm-package sources
                  file: "elm-package.json"
                }],
                package_manager: "elm-package"
              )
          end

          dependency_set.dependencies.sort_by(&:name)
        end

        private

        def check_required_files
          raise "No elm-package.json!" unless elm_package_file
        end

        def max_version_for(version_requirement)
          unless version_requirement.match?(REQUIREMENT_REGEX)
            raise "Unexpected elm version format: #{version_requirement}"
          end

          requirement_parts = version_requirement.match(REQUIREMENT_REGEX).
                              named_captures

          patch = requirement_parts.fetch("patch").to_i
          minor = requirement_parts.fetch("minor").to_i
          major = requirement_parts.fetch("major").to_i

          if requirement_parts.fetch("operator") == "<"
            if patch.positive?
              patch -= 1
            elsif minor.positive?
              patch = MAX_VERSION # SORRY NOT SORRY
              minor -= 1
            elsif major > 1
              minor = MAX_VERSION
              patch = MAX_VERSION
              major -= 1
            end
          end
          Dependabot::Utils::Elm::Version.new("#{major}.#{minor}.#{patch}")
        end

        def parsed_package_file
          @parsed_package_file ||= JSON.parse(elm_package_file.content)
        end

        def elm_package_file
          @elm_package_file ||= get_original_file("elm-package.json")
        end
      end
    end
  end
end
