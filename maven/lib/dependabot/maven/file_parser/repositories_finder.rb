# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency_file"
require "dependabot/maven/file_parser"
require "dependabot/shared_helpers"
require "dependabot/errors"

# For documentation, see:
# - http://maven.apache.org/pom.html#Repositories
# - http://maven.apache.org/guides/mini/guide-multiple-repositories.html
module Dependabot
  module Maven
    class FileParser
      class RepositoriesFinder
        require_relative "property_value_finder"
        # In theory we should check the artifact type and either look in
        # <repositories> or <pluginRepositories>. In practice it's unlikely
        # anyone makes this distinction.
        REPOSITORY_SELECTOR = "repositories > repository, "\
                              "pluginRepositories > pluginRepository"

        # The Central Repository is included in the Super POM, which is
        # always inherited from.
        CENTRAL_REPO_URL = ENV['DEPENDABOT_MAVEN_CENTRAL_REPO_URL'] || "https://repo.maven.apache.org/maven2"

        def initialize(dependency_files:, evaluate_properties: true)
          @dependency_files = dependency_files

          # We need the option not to evaluate properties so as not to have a
          # circular dependency between this class and the PropertyValueFinder
          # class
          @evaluate_properties = evaluate_properties
        end

        # Collect all repository URLs from this POM and its parents
        def repository_urls(pom:, exclude_inherited: false)
          repo_urls_in_pom =
            Nokogiri::XML(pom.content).
            css(REPOSITORY_SELECTOR).
            map { |node| node.at_css("url").content.strip.gsub(%r{/$}, "") }.
            reject { |url| contains_property?(url) && !evaluate_properties? }.
            select { |url| url.start_with?("http") }.
            map { |url| evaluated_value(url, pom) }

          return repo_urls_in_pom + [CENTRAL_REPO_URL] if exclude_inherited

          unless (parent = parent_pom(pom, repo_urls_in_pom))
            return repo_urls_in_pom + [CENTRAL_REPO_URL]
          end

          repo_urls_in_pom + repository_urls(pom: parent)
        end

        private

        attr_reader :dependency_files

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

          return internal_dependency_poms[name] if internal_dependency_poms[name]

          return unless version && !version.include?(",")

          fetch_remote_parent_pom(group_id, artifact_id, version, repo_urls)
        end
        # rubocop:enable Metrics/PerceivedComplexity

        def internal_dependency_poms
          return @internal_dependency_poms if @internal_dependency_poms

          @internal_dependency_poms = {}
          dependency_files.each do |pom|
            doc = Nokogiri::XML(pom.content)
            group_id = doc.at_css("project > groupId") ||
                       doc.at_css("project > parent > groupId")
            artifact_id = doc.at_css("project > artifactId")

            next unless group_id && artifact_id

            dependency_name = [
              group_id.content.strip,
              artifact_id.content.strip
            ].join(":")

            @internal_dependency_poms[dependency_name] = pom
          end

          @internal_dependency_poms
        end

        def fetch_remote_parent_pom(group_id, artifact_id, version, repo_urls)
          (repo_urls + [CENTRAL_REPO_URL]).uniq.each do |base_url|
            url = remote_pom_url(group_id, artifact_id, version, base_url)

            @maven_responses ||= {}
            @maven_responses[url] ||= Excon.get(
              url,
              idempotent: true,
              **SharedHelpers.excon_defaults
            )
            next unless @maven_responses[url].status == 200
            next unless pom?(@maven_responses[url].body)

            dependency_file = DependencyFile.new(
              name: "remote_pom.xml",
              content: @maven_responses[url].body
            )

            return dependency_file
          rescue Excon::Error::Socket, Excon::Error::Timeout,
                 Excon::Error::TooManyRedirects, URI::InvalidURIError
            nil
          end

          # If a parent POM couldn't be found, return `nil`
          nil
        end

        def remote_pom_url(group_id, artifact_id, version, base_repo_url)
          "#{base_repo_url}/"\
          "#{group_id.tr('.', '/')}/#{artifact_id}/#{version}/"\
          "#{artifact_id}-#{version}.pom"
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
            PropertyValueFinder.new(dependency_files: dependency_files)
        end

        def property_regex
          Maven::FileParser::PROPERTY_REGEX
        end

        def pom?(content)
          !Nokogiri::XML(content).at_css("project > artifactId").nil?
        end
      end
    end
  end
end
