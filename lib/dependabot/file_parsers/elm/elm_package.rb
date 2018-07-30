# frozen_string_literal: true
require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/file_fetchers/elm/elm_package"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module Elm
      class ElmPackage < Dependabot::FileParsers::Base
        MAX_VERSION = Float::INFINITY
        require "dependabot/file_parsers/base/dependency_set"

        def parse
          self.class.dependency_set_for(elm_package_file.content)
        end

        def self.dependency_set_for(content)
          dependency_set = DependencySet.new

          decode(content).each do |dep|
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

        private_class_method def self.decode(content)
          json = JSON.parse content

          json['dependencies'].
            map {|k,v| {name: k, requirement: v, file: "elm-package.json", max_version: max_of(v)}}
        end

        private_class_method def self.max_of(version_requirement)
          _, maybe_equals, *major_minor_patch = /<(=)? (\d+)\.(\d+)\.(\d+)$/.match(version_requirement).to_a
          major, minor, patch = major_minor_patch.map(&:to_i)
          if maybe_equals != "="
            if patch > 0
              patch-=1
            elsif minor > 0
              patch = MAX_VERSION # SORRY NOT SORRY
              minor-=1
            elsif major > 1
              minor = MAX_VERSION
              patch = MAX_VERSION
              major-=1
            end
          end
          [major, minor, patch]
        end

        private

        def check_required_files
          raise "No elm-package.json!" unless elm_package_file
        end


        def elm_package_file
          @elm_package_file ||= get_original_file("elm-package.json")
        end
      end
    end
  end
end
