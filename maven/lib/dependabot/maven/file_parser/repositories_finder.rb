# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency_file"
require "dependabot/maven/file_parser"
require "dependabot/registry_client"
require "dependabot/errors"

# For documentation, see:
# - http://maven.apache.org/pom.html#Repositories
# - http://maven.apache.org/guides/mini/guide-multiple-repositories.html
module Dependabot
  module Maven
    class FileParser
      class RepositoriesFinder
        require_relative "property_value_finder"
        require_relative "pom_fetcher"
        # In theory we should check the artifact type and either look in
        # <repositories> or <pluginRepositories>. In practice it's unlikely
        # anyone makes this distinction.
        REPOSITORY_SELECTOR = "repositories > repository, " \
                              "pluginRepositories > pluginRepository"

        def initialize(pom_fetcher:, dependency_files: [], credentials: [], evaluate_properties: true)
          @pom_fetcher = pom_fetcher
          @dependency_files = dependency_files
          @credentials = credentials

          # We need the option not to evaluate properties so as not to have a
          # circular dependency between this class and the PropertyValueFinder
          # class
          @evaluate_properties = evaluate_properties
          # Aggregates URLs seen in POMs to avoid short term memory loss.
          # For instance a repository in a child POM might apply to the parent too.
          @known_urls = []
        end

        def central_repo_url
          base = @credentials.find { |cred| cred["type"] == "maven_repository" && cred["replaces-base"] == true }
          base ? base["url"] : "https://repo.maven.apache.org/maven2"
        end

        # Collect all repository URLs from this POM and its parents
        def repository_urls(pom:, exclude_inherited: false)
          entries = gather_repository_urls(pom: pom, exclude_inherited: exclude_inherited)
          ids = Set.new
          @known_urls += entries.map do |entry|
            next if entry[:id] && ids.include?(entry[:id])

            ids.add(entry[:id]) unless entry[:id].nil?
            entry
          end
          @known_urls = @known_urls.uniq.compact

          urls = urls_from_credentials + @known_urls.map { |entry| entry[:url] }
          urls += [central_repo_url] unless @known_urls.any? { |entry| entry[:id] == super_pom[:id] }
          urls.uniq
        end

        private

        attr_reader :dependency_files

        # The Central Repository is included in the Super POM, which is
        # always inherited from.
        def super_pom
          { url: central_repo_url, id: "central" }
        end

        def gather_repository_urls(pom:, exclude_inherited: false)
          repos_in_pom =
            Nokogiri::XML(pom.content).
            css(REPOSITORY_SELECTOR).
            map { |node| { url: node.at_css("url").content.strip, id: node.at_css("id").content.strip } }.
            reject { |entry| contains_property?(entry[:url]) && !evaluate_properties? }.
            select { |entry| entry[:url].start_with?("http") }.
            map { |entry| { url: evaluated_value(entry[:url], pom).gsub(%r{/$}, ""), id: entry[:id] } }

          return repos_in_pom if exclude_inherited

          urls_in_pom = repos_in_pom.map { |repo| repo[:url] }
          unless (parent = parent_pom(pom, urls_in_pom))
            return repos_in_pom
          end

          repos_in_pom + gather_repository_urls(pom: parent)
        end

        def evaluate_properties?
          @evaluate_properties
        end

        # rubocop:disable Metrics/PerceivedComplexity
        def parent_pom(pom, repo_urls)
          doc = Nokogiri::XML(pom.content)
          doc.remove_namespaces!
          group_id = doc.at_xpath("/project/parent/groupId")&.content&.strip
          artifact_id =
            doc.at_xpath("/project/parent/artifactId")&.content&.strip
          version = doc.at_xpath("/project/parent/version")&.content&.strip

          return unless group_id && artifact_id

          name = [group_id, artifact_id].join(":")

          return @pom_fetcher.internal_dependency_poms[name] if @pom_fetcher.internal_dependency_poms[name]

          return unless version && !version.include?(",")

          urls = urls_from_credentials + repo_urls + [central_repo_url]
          @pom_fetcher.fetch_remote_parent_pom(group_id, artifact_id, version, urls)
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def urls_from_credentials
          @credentials.
            select { |cred| cred["type"] == "maven_repository" }.
            filter_map { |cred| cred["url"]&.strip&.gsub(%r{/$}, "") }
        end

        def contains_property?(value)
          value.match?(property_regex)
        end

        def evaluated_value(value, pom)
          return value unless contains_property?(value)

          property_name = value.match(property_regex).
                          named_captures.fetch("property")
          property_value = value_for_property(property_name, pom)

          value.gsub(property_regex, property_value)
        end

        def value_for_property(property_name, pom)
          value =
            property_value_finder.
            property_details(
              property_name: property_name,
              callsite_pom: pom
            )&.fetch(:value)

          return value if value

          msg = "Property not found: #{property_name}"
          raise DependencyFileNotEvaluatable, msg
        end

        # Cached, since this can makes calls to the registry (to get property
        # values from parent POMs)
        def property_value_finder
          @property_value_finder ||=
            PropertyValueFinder.new(dependency_files: dependency_files, credentials: @credentials)
        end

        def property_regex
          Maven::FileParser::PROPERTY_REGEX
        end
      end
    end
  end
end
