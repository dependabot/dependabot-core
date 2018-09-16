# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency"
require "dependabot/file_parsers/dotnet/nuget"

# For details on how dotnet handles version constraints, see:
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning
module Dependabot
  module FileParsers
    module Dotnet
      class Nuget
        class ProjectFileParser
          require "dependabot/file_parsers/base/dependency_set"
          require_relative "property_value_finder"

          DEPENDENCY_SELECTOR = "ItemGroup > PackageReference, "\
                                "ItemGroup > Dependency, "\
                                "ItemGroup > DevelopmentDependency"

          PROPERTY_REGEX      = /\$\((?<property>.*?)\)/

          def initialize(project_file:)
            @project_file = project_file
          end

          def dependency_set
            dependency_set = Dependabot::FileParsers::Base::DependencySet.new

            doc = Nokogiri::XML(project_file.content)
            doc.remove_namespaces!
            doc.css(DEPENDENCY_SELECTOR).each do |dependency_node|
              next unless dependency_name(dependency_node)

              requirement = {
                requirement: dependency_requirement(dependency_node),
                file: project_file.name,
                groups: [],
                source: nil
              }

              if req_property_name(dependency_node)
                requirement[:metadata] =
                  { property_name: req_property_name(dependency_node) }
              end

              dependency_set <<
                Dependency.new(
                  name: dependency_name(dependency_node),
                  version: dependency_version(dependency_node),
                  package_manager: "nuget",
                  requirements: [requirement]
                )
            end

            dependency_set
          end

          private

          attr_reader :project_file

          def dependency_name(dependency_node)
            raw_name =
              dependency_node.attribute("Include")&.value&.strip ||
              dependency_node.at_xpath("./Include")&.content&.strip
            return unless raw_name

            evaluated_value(raw_name)
          end

          def dependency_requirement(dependency_node)
            raw_requirement =
              dependency_node.attribute("Version")&.value&.strip ||
              dependency_node.at_xpath("./Version")&.content&.strip
            return unless raw_requirement

            evaluated_value(raw_requirement)
          end

          def dependency_version(dependency_node)
            requirement = dependency_requirement(dependency_node)
            return unless requirement

            # Remove brackets if present
            version = requirement.gsub(/[\(\)\[\]]/, "").strip

            # Take the first (and therefore lowest) element of any range. Nuget
            # resolves dependencies to the "Lowest Applicable Version".
            # https://docs.microsoft.com/en-us/nuget/consume-packages/dependency-resolution
            version = version.split(",").first.strip

            # We don't know the version for requirements like (,1.0) or for
            # wildcard requirements, so return `nil` for these.
            return version unless version == "" || version.include?("*")
          end

          def req_property_name(dependency_node)
            raw_requirement =
              dependency_node.attribute("Version")&.value&.strip ||
              dependency_node.at_xpath("./Version")&.content&.strip
            return unless raw_requirement

            return unless raw_requirement.match?(PROPERTY_REGEX)

            raw_requirement.
              match(PROPERTY_REGEX).
              named_captures.fetch("property")
          end

          def evaluated_value(value)
            return value unless value.match?(PROPERTY_REGEX)

            property_name = value.match(PROPERTY_REGEX).
                            named_captures.fetch("property")
            property_value = value_for_property(property_name)

            # Don't halt parsing for a missing property value until we're
            # confident we're fetching property values correctly
            return value unless property_value

            value.gsub(PROPERTY_REGEX, property_value)
          end

          def value_for_property(property_name)
            property_value_finder.
              property_details(property_name: property_name)&.
              fetch(:value)
          end

          def property_value_finder
            @property_value_finder ||=
              PropertyValueFinder.new(project_file: project_file)
          end
        end
      end
    end
  end
end
