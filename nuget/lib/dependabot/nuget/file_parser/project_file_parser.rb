# typed: true
# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency"
require "dependabot/nuget/file_parser"
require "dependabot/nuget/update_checker"
require "dependabot/nuget/cache_manager"

# For details on how dotnet handles version constraints, see:
# https://docs.microsoft.com/en-us/nuget/reference/package-versioning
module Dependabot
  module Nuget
    class FileParser
      # rubocop:disable Metrics/ClassLength
      class ProjectFileParser
        require "dependabot/file_parsers/base/dependency_set"
        require_relative "property_value_finder"
        require_relative "../update_checker/repository_finder"

        DEPENDENCY_SELECTOR = "ItemGroup > PackageReference, " \
                              "ItemGroup > GlobalPackageReference, " \
                              "ItemGroup > PackageVersion, " \
                              "ItemGroup > Dependency, " \
                              "ItemGroup > DevelopmentDependency"

        PROJECT_REFERENCE_SELECTOR = "ItemGroup > ProjectReference"

        PACKAGE_REFERENCE_SELECTOR = "ItemGroup > PackageReference, " \
                                     "ItemGroup > GlobalPackageReference"

        PACKAGE_VERSION_SELECTOR = "ItemGroup > PackageVersion"

        PROJECT_SDK_REGEX   = %r{^([^/]+)/(\d+(?:[.]\d+(?:[.]\d+)?)?(?:[+-].*)?)$}
        PROPERTY_REGEX      = /\$\((?<property>.*?)\)/
        ITEM_REGEX          = /\@\((?<property>.*?)\)/

        def self.dependency_set_cache
          CacheManager.cache("project_file_dependency_set")
        end

        def self.dependency_url_search_cache
          CacheManager.cache("dependency_url_search_cache")
        end

        def initialize(dependency_files:, credentials:)
          @dependency_files       = dependency_files
          @credentials            = credentials
        end

        def dependency_set(project_file:)
          return parse_dependencies(project_file) if CacheManager.caching_disabled?

          key = "#{project_file.name.downcase}::#{project_file.content.hash}"
          cache = ProjectFileParser.dependency_set_cache

          cache[key] ||= parse_dependencies(project_file)

          dependency_set = Dependabot::FileParsers::Base::DependencySet.new
          dependency_set += cache[key]
          dependency_set
        end

        def target_frameworks(project_file:)
          target_framework = details_for_property("TargetFramework", project_file)
          return [target_framework&.fetch(:value)] if target_framework

          target_frameworks = details_for_property("TargetFrameworks", project_file)
          return target_frameworks&.fetch(:value)&.split(";") if target_frameworks

          target_framework = details_for_property("TargetFrameworkVersion", project_file)
          return [] unless target_framework

          # TargetFrameworkVersion is a string like "v4.7.2"
          value = target_framework&.fetch(:value)
          # convert it to a string like "net472"
          ["net#{value[1..-1].delete('.')}"]
        end

        def nuget_configs
          dependency_files.select { |f| f.name.match?(%r{(^|/)nuget\.config$}i) }
        end

        private

        attr_reader :dependency_files, :credentials

        def parse_dependencies(project_file)
          dependency_set = Dependabot::FileParsers::Base::DependencySet.new

          doc = Nokogiri::XML(project_file.content)
          doc.remove_namespaces!
          # Look for regular package references
          doc.css(DEPENDENCY_SELECTOR).each do |dependency_node|
            name = dependency_name(dependency_node, project_file)
            req = dependency_requirement(dependency_node, project_file)
            version = dependency_version(dependency_node, project_file)
            prop_name = req_property_name(dependency_node)
            is_dev = dependency_node.name == "DevelopmentDependency"

            dependency = build_dependency(name, req, version, prop_name, project_file, dev: is_dev)
            dependency_set << dependency if dependency
          end

          add_global_package_references(dependency_set)

          add_transitive_dependencies(project_file, doc, dependency_set)

          # Look for SDK references; see:
          # https://docs.microsoft.com/en-us/visualstudio/msbuild/how-to-use-project-sdk
          add_sdk_references(doc, dependency_set, project_file)

          dependency_set
        end

        def add_global_package_references(dependency_set)
          project_import_files.each do |file|
            doc = Nokogiri::XML(file.content)
            doc.remove_namespaces!

            doc.css(PACKAGE_REFERENCE_SELECTOR).each do |dependency_node|
              name = dependency_name(dependency_node, file)
              req = dependency_requirement(dependency_node, file)
              version = dependency_version(dependency_node, file)
              prop_name = req_property_name(dependency_node)

              dependency = build_dependency(name, req, version, prop_name, file)
              dependency_set << dependency if dependency
            end
          end
        end

        def add_transitive_dependencies(project_file, doc, dependency_set)
          add_transitive_dependencies_from_packages(dependency_set)
          add_transitive_dependencies_from_project_references(project_file, doc, dependency_set)
        end

        def add_transitive_dependencies_from_project_references(project_file, doc, dependency_set)
          project_file_directory = File.dirname(project_file.name)
          is_rooted = project_file_directory.start_with?("/")
          # Root the directory path to avoid expand_path prepending the working directory
          project_file_directory = "/" + project_file_directory unless is_rooted

          # Look for regular project references
          doc.css(PROJECT_REFERENCE_SELECTOR).each do |reference_node|
            relative_path = dependency_name(reference_node, project_file)
            # This could result from a <ProjectReference Remove="..." /> item.
            next unless relative_path

            # normalize path separators
            relative_path = relative_path.tr("\\", "/")
            # path is relative to the project file directory
            relative_path = File.join(project_file_directory, relative_path)

            # get absolute path
            full_path = File.expand_path(relative_path)
            full_path = full_path[1..-1] unless is_rooted

            referenced_file = dependency_files.find { |f| f.name == full_path }
            next unless referenced_file

            dependency_set(project_file: referenced_file).dependencies.each do |dep|
              dependency = Dependency.new(
                name: dep.name,
                version: dep.version,
                package_manager: dep.package_manager,
                requirements: []
              )
              dependency_set << dependency
            end
          end
        end

        def add_transitive_dependencies_from_packages(dependency_set)
          transitive_dependencies_from_packages(dependency_set.dependencies).each { |dep| dependency_set << dep }
        end

        def transitive_dependencies_from_packages(dependencies)
          transitive_dependencies = {}

          dependencies.each do |dependency|
            UpdateChecker::DependencyFinder.new(
              dependency: dependency,
              dependency_files: dependency_files,
              credentials: credentials
            ).transitive_dependencies.each do |transitive_dep|
              visited_dep = transitive_dependencies[transitive_dep.name.downcase]
              next if !visited_dep.nil? && visited_dep.numeric_version > transitive_dep.numeric_version

              transitive_dependencies[transitive_dep.name.downcase] = transitive_dep
            end
          end

          transitive_dependencies.values
        end

        def add_sdk_references(doc, dependency_set, project_file)
          # These come in 3 flavours:
          # - <Project Sdk="Name/Version">
          # - <Sdk Name="Name" Version="Version" />
          # - <Import Project="..." Sdk="Name" Version="Version" />
          # None of these support the use of properties, nor do they allow child
          # elements instead of attributes.
          add_sdk_refs_from_project(doc, dependency_set, project_file)
          add_sdk_refs_from_sdk_tags(doc, dependency_set, project_file)
          add_sdk_refs_from_import_tags(doc, dependency_set, project_file)
        end

        def add_sdk_ref_from_project(sdk_references, dependency_set, project_file)
          sdk_references.split(";")&.each do |sdk_reference|
            m = sdk_reference.match(PROJECT_SDK_REGEX)
            if m
              dependency = build_dependency(m[1], m[2], m[2], nil, project_file)
              dependency_set << dependency if dependency
            end
          end
        end

        def add_sdk_refs_from_import_tags(doc, dependency_set, project_file)
          doc.xpath("/Project/Import").each do |import_node|
            next unless import_node.attribute("Sdk") && import_node.attribute("Version")

            name = import_node.attribute("Sdk")&.value&.strip
            version = import_node.attribute("Version")&.value&.strip

            dependency = build_dependency(name, version, version, nil, project_file)
            dependency_set << dependency if dependency
          end
        end

        def add_sdk_refs_from_project(doc, dependency_set, project_file)
          doc.xpath("/Project").each do |project_node|
            sdk_references = project_node.attribute("Sdk")&.value&.strip
            next unless sdk_references

            add_sdk_ref_from_project(sdk_references, dependency_set, project_file)
          end
        end

        def add_sdk_refs_from_sdk_tags(doc, dependency_set, project_file)
          doc.xpath("/Project/Sdk").each do |sdk_node|
            next unless sdk_node.attribute("Version")

            name = sdk_node.attribute("Name")&.value&.strip
            version = sdk_node.attribute("Version")&.value&.strip

            dependency = build_dependency(name, version, version, nil, project_file)
            dependency_set << dependency if dependency
          end
        end

        def build_dependency(name, req, version, prop_name, project_file, dev: false)
          return unless name

          # Exclude any dependencies specified using interpolation
          return if [name, req, version].any? { |s| s&.include?("%(") }

          requirement = {
            requirement: req,
            file: project_file.name,
            groups: [dev ? "devDependencies" : "dependencies"],
            source: nil
          }

          if prop_name
            # Get the root property name unless no details could be found,
            # in which case use the top-level name to ease debugging
            root_prop_name = details_for_property(prop_name, project_file)
                             &.fetch(:root_property_name) || prop_name
            requirement[:metadata] = { property_name: root_prop_name }
          end

          dependency = Dependency.new(
            name: name,
            version: version,
            package_manager: "nuget",
            requirements: [requirement]
          )

          # only include dependency if one of the sources has it
          return unless dependency_has_search_results?(dependency)

          dependency
        end

        def dependency_has_search_results?(dependency)
          dependency_urls = UpdateChecker::RepositoryFinder.new(
            dependency: dependency,
            credentials: credentials,
            config_files: nuget_configs
          ).dependency_urls
          if dependency_urls.empty?
            dependency_urls = [UpdateChecker::RepositoryFinder.get_default_repository_details(dependency.name)]
          end
          dependency_urls.any? do |dependency_url|
            dependency_url_has_matching_result?(dependency.name, dependency_url)
          end
        end

        def dependency_url_has_matching_result?(dependency_name, dependency_url)
          repository_type = dependency_url.fetch(:repository_type)
          if repository_type == "v3"
            dependency_url_has_matching_result_v3?(dependency_name, dependency_url)
          elsif repository_type == "v2"
            dependency_url_has_matching_result_v2?(dependency_name, dependency_url)
          else
            raise "Unknown repository type: #{repository_type}"
          end
        end

        def dependency_url_has_matching_result_v3?(dependency_name, dependency_url)
          url = dependency_url.fetch(:search_url)
          auth_header = dependency_url.fetch(:auth_header)
          response = execute_search_for_dependency_url(url, auth_header)
          return false unless response.status == 200

          body = JSON.parse(response.body)
          data = body["data"]
          return false unless data.length.positive?

          data.any? { |result| result["id"].casecmp?(dependency_name) }
        end

        def dependency_url_has_matching_result_v2?(dependency_name, dependency_url)
          url = dependency_url.fetch(:versions_url)
          auth_header = dependency_url.fetch(:auth_header)
          response = execute_search_for_dependency_url(url, auth_header)
          return false unless response.status == 200

          doc = Nokogiri::XML(response.body)
          doc.remove_namespaces!
          id_nodes = doc.xpath("/feed/entry/properties/Id")
          found_matching_result = id_nodes.any? do |id_node|
            return false unless id_node.text

            id_node.text.casecmp?(dependency_name)
          end
          found_matching_result
        end

        def execute_search_for_dependency_url(url, auth_header)
          cache = ProjectFileParser.dependency_url_search_cache
          cache[url] ||= Dependabot::RegistryClient.get(
            url: url,
            headers: auth_header
          )

          cache[url]
        end

        def dependency_name(dependency_node, project_file)
          raw_name = get_attribute_value(dependency_node, "Include") ||
                     get_attribute_value(dependency_node, "Update")
          return unless raw_name

          # If the item contains @(ItemGroup) then ignore as it
          # updates a set of ItemGroup elements
          return if raw_name.match?(ITEM_REGEX)

          evaluated_value(raw_name, project_file)
        end

        def dependency_requirement(dependency_node, project_file)
          raw_requirement = get_node_version_value(dependency_node) ||
                            find_package_version(dependency_node, project_file)
          return unless raw_requirement

          evaluated_value(raw_requirement, project_file)
        end

        def find_package_version(dependency_node, project_file)
          name = dependency_name(dependency_node, project_file)
          return unless name

          package_version_string = package_versions[name].to_s
          return unless package_version_string != ""

          package_version_string
        end

        def package_versions
          @package_versions ||= begin
            package_versions = {}
            directory_packages_props_files.each do |file|
              doc = Nokogiri::XML(file.content)
              doc.remove_namespaces!
              doc.css(PACKAGE_VERSION_SELECTOR).each do |package_node|
                name = dependency_name(package_node, file)
                version = dependency_version(package_node, file)
                next unless name && version

                version = Version.new(version)
                existing_version = package_versions[name]
                next if existing_version && existing_version > version

                package_versions[name] = version
              end
            end
            package_versions
          end
        end

        def directory_packages_props_files
          dependency_files.select { |df| df.name.match?(/[Dd]irectory.[Pp]ackages.props/) }
        end

        def dependency_version(dependency_node, project_file)
          requirement = dependency_requirement(dependency_node, project_file)
          return unless requirement

          # Remove brackets if present
          version = requirement.gsub(/[\(\)\[\]]/, "").strip

          # We don't know the version for range requirements or wildcard
          # requirements, so return `nil` for these.
          return if version.include?(",") || version.include?("*") ||
                    version == ""

          version
        end

        def req_property_name(dependency_node)
          raw_requirement = get_node_version_value(dependency_node)
          return unless raw_requirement

          return unless raw_requirement.match?(PROPERTY_REGEX)

          raw_requirement
            .match(PROPERTY_REGEX)
            .named_captures.fetch("property")
        end

        def get_node_version_value(node)
          get_attribute_value(node, "Version") || get_attribute_value(node, "VersionOverride")
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def get_attribute_value(node, attribute)
          value =
            node.attribute(attribute)&.value&.strip ||
            node.at_xpath("./#{attribute}")&.content&.strip ||
            node.attribute(attribute.downcase)&.value&.strip ||
            node.at_xpath("./#{attribute.downcase}")&.content&.strip

          value == "" ? nil : value
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def evaluated_value(value, project_file)
          return value unless value.match?(PROPERTY_REGEX)

          property_name = value.match(PROPERTY_REGEX)
                               .named_captures.fetch("property")
          property_details = details_for_property(property_name, project_file)

          # Don't halt parsing for a missing property value until we're
          # confident we're fetching property values correctly
          return value unless property_details&.fetch(:value)

          value.gsub(PROPERTY_REGEX, property_details&.fetch(:value))
        end

        def details_for_property(property_name, project_file)
          property_value_finder
            .property_details(
              property_name: property_name,
              callsite_file: project_file
            )
        end

        def property_value_finder
          @property_value_finder ||=
            PropertyValueFinder.new(dependency_files: dependency_files)
        end

        def project_import_files
          dependency_files -
            project_files -
            packages_config_files -
            nuget_configs -
            [global_json] -
            [dotnet_tools_json]
        end

        def project_files
          dependency_files.select { |f| f.name.match?(/\.[a-z]{2}proj$/) }
        end

        def packages_config_files
          dependency_files.select do |f|
            f.name.split("/").last.casecmp("packages.config").zero?
          end
        end

        def global_json
          dependency_files.find { |f| f.name.casecmp("global.json").zero? }
        end

        def dotnet_tools_json
          dependency_files.find { |f| f.name.casecmp(".config/dotnet-tools.json").zero? }
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
