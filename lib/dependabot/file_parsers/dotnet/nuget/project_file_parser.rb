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

          def initialize(dependency_files:)
            @dependency_files = dependency_files
          end

          def dependency_set(project_file:)
            dependency_set = Dependabot::FileParsers::Base::DependencySet.new

            doc = Nokogiri::XML(project_file.content)
            doc.remove_namespaces!
            doc.css(DEPENDENCY_SELECTOR).each do |dependency_node|
              name = dependency_name(dependency_node, project_file)
              req = dependency_requirement(dependency_node, project_file)
              version = dependency_version(dependency_node, project_file)
              prop_name = req_property_name(dependency_node)

              dependency =
                build_dependency(name, req, version, prop_name, project_file)
              dependency_set << dependency if dependency
            end

            dependency_set
          end

          private

          attr_reader :dependency_files

          def build_dependency(name, req, version, prop_name, project_file)
            return unless name

            # Exclude any dependencies specified using interpolation
            return if [name, req, version].any? { |s| s&.include?("%(") }

            requirement = {
              requirement: req,
              file: project_file.name,
              groups: [],
              source: nil
            }
            requirement[:metadata] = { property_name: prop_name } if prop_name

            Dependency.new(
              name: name,
              version: version,
              package_manager: "nuget",
              requirements: [requirement]
            )
          end

          def dependency_name(dependency_node, project_file)
            raw_name =
              dependency_node.attribute("Include")&.value&.strip ||
              dependency_node.at_xpath("./Include")&.content&.strip
            return unless raw_name

            evaluated_value(raw_name, project_file)
          end

          def dependency_requirement(dependency_node, project_file)
            raw_requirement =
              dependency_node.attribute("Version")&.value&.strip ||
              dependency_node.at_xpath("./Version")&.content&.strip
            return unless raw_requirement

            evaluated_value(raw_requirement, project_file)
          end

          def dependency_version(dependency_node, project_file)
            requirement = dependency_requirement(dependency_node, project_file)
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

          def evaluated_value(value, project_file)
            return value unless value.match?(PROPERTY_REGEX)

            property_name = value.match(PROPERTY_REGEX).
                            named_captures.fetch("property")
            property_value = value_for_property(property_name, project_file)

            # Don't halt parsing for a missing property value until we're
            # confident we're fetching property values correctly
            return value unless property_value

            value.gsub(PROPERTY_REGEX, property_value)
          end

          def value_for_property(property_name, project_file)
            property_value_finder.
              property_details(
                property_name: property_name,
                callsite_file: project_file
              )&.fetch(:value)
          end

          def property_value_finder
            @property_value_finder ||=
              PropertyValueFinder.new(dependency_files: dependency_files)
          end
        end
      end
    end
  end
end
