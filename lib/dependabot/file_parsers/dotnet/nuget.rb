# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency"
require "dependabot/file_parsers/base"

# For details on how dotnet handles version constraints, see:
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning
module Dependabot
  module FileParsers
    module Dotnet
      class Nuget < Dependabot::FileParsers::Base
        require "dependabot/file_parsers/base/dependency_set"

        DEPENDENCY_SELECTOR = "ItemGroup > PackageReference"

        def parse
          dependency_set = DependencySet.new
          dependency_set += project_file_dependencies
          dependency_set.dependencies
        end

        private

        def project_file_dependencies
          dependency_set = DependencySet.new

          (project_files + project_import_files).each do |proj_file|
            doc = Nokogiri::XML(proj_file.content)
            doc.remove_namespaces!
            doc.css(DEPENDENCY_SELECTOR).each do |dependency_node|
              dependency_set <<
                Dependency.new(
                  name: dependency_name(dependency_node),
                  version: dependency_version(dependency_node),
                  package_manager: "nuget",
                  requirements: [{
                    requirement: dependency_requirement(dependency_node),
                    file: proj_file.name,
                    groups: [],
                    source: nil
                  }]
                )
            end
          end

          dependency_set
        end

        def dependency_name(dependency_node)
          dependency_node.attribute("Include")&.value&.strip ||
            dependency_node.at_xpath("./Include")&.content&.strip
        end

        def dependency_requirement(dependency_node)
          dependency_node.attribute("Version")&.value&.strip ||
            dependency_node.at_xpath("./Version")&.content&.strip
        end

        def dependency_version(dependency_node)
          requirement = dependency_requirement(dependency_node)

          # Remove brackets if present
          version = requirement.gsub(/[\(\)\[\]]/, "").strip

          # Take the first (and therefore lowest) element of any range. Nuget
          # resolves dependencies to the "Lowest Applicable Version".
          # https://docs.microsoft.com/en-us/nuget/consume-packages/dependency-
          #   resolution
          version = version.split(",").first.strip

          # We don't know the version for requirements like (,1.0) or for
          # wildcard requirements, so return `nil` for these.
          return version unless version == "" || version.include?("*")
        end

        def project_files
          dependency_files.
            select { |df| df.name.match?(/\.(cs|vb|fs)proj$/) }.
            reject { |df| df.type == "project_import" }
        end

        def project_import_files
          dependency_files.select { |df| df.type == "project_import" }
        end

        def check_required_files
          return if project_files.any?
          raise "No project file!"
        end
      end
    end
  end
end
