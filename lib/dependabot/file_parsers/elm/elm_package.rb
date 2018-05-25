# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/file_fetchers/elm/elm_package"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module Elm
      class ElmPackage < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/base/dependency_set"

        def parse
          dependency_set = DependencySet.new

          dependency_details.each do |dep|
            git_dependency = dep["source"]&.fetch("type") == "git"

            dependency_set <<
              Dependency.new(
                name: dep[:name],
                version: dep[:max_version],
                requirements: [{
                  requirement: dep[:requirement], # 4.0 <= v <= 4.0
                  groups: nil, # we don't have this (its dev vs non-dev)
                  source: nil, # elm-package has no git or non-elm-package sources
                  file: dep[:file]
                }],
                package_manager: "elm-package"
              )
          end

          dependency_set.dependencies.sort_by(&:name)
        end

        def check_required_files
          raise "No elm-package.json!" unless elm_package
        end

        private

        def dependency_details
          json = JSON.parse(elm_package)
          json['dependencies'].
            map {|k,v| {name: k, requirement: v, file: "elm-package.json", max_version: max_of(v)}}
        end

        def max_of(version_requirement)
          _, maybe_equals, *major_minor_patch = /\<(=)? (\d)\.(\d)\.(\d)$/.match(version_requirement)
          major, minor, patch = major_minor_patch.map(&:to_i)
          if maybe_equals != "="
            if patch > 0
              patch-=1
            elsif minor > 0
              minor-=1
            elsif major > 0
              major-=1
            end
          end
          [major, minor, patch]
        end

        def elm_package
          @elm_package ||= get_original_file("elm-package.json")
        end
      end
    end
  end
end
