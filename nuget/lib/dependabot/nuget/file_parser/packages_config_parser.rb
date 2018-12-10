# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency"
require "dependabot/file_parsers/dotnet/nuget"

# For details on packages.config files see:
# https://docs.microsoft.com/en-us/nuget/reference/packages-config
module Dependabot
  module FileParsers
    module Dotnet
      class Nuget
        class PackagesConfigParser
          require "dependabot/file_parsers/base/dependency_set"

          DEPENDENCY_SELECTOR = "packages > package"

          def initialize(packages_config:)
            @packages_config = packages_config
          end

          def dependency_set
            dependency_set = Dependabot::FileParsers::Base::DependencySet.new

            doc = Nokogiri::XML(packages_config.content)
            doc.remove_namespaces!
            doc.css(DEPENDENCY_SELECTOR).each do |dependency_node|
              dependency_set <<
                Dependency.new(
                  name: dependency_name(dependency_node),
                  version: dependency_version(dependency_node),
                  package_manager: "nuget",
                  requirements: [{
                    requirement: dependency_version(dependency_node),
                    file: packages_config.name,
                    groups: [],
                    source: nil
                  }]
                )
            end

            dependency_set
          end

          private

          attr_reader :packages_config

          def dependency_name(dependency_node)
            dependency_node.attribute("id")&.value&.strip ||
              dependency_node.at_xpath("./id")&.content&.strip
          end

          def dependency_version(dependency_node)
            # Ranges and wildcards aren't allowed in a packages.config - the
            # specified requirement is always an exact version.
            dependency_node.attribute("version")&.value&.strip ||
              dependency_node.at_xpath("./version")&.content&.strip
          end
        end
      end
    end
  end
end
