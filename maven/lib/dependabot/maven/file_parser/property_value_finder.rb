# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "sorbet-runtime"
require "dependabot/dependency_file"
require "dependabot/maven/file_parser"
require "dependabot/registry_client"

# For documentation, see:
# - http://maven.apache.org/guides/introduction/introduction-to-the-pom.html
# - http://maven.apache.org/pom.html#Properties
module Dependabot
  module Maven
    class FileParser
      class PropertyValueFinder
        extend T::Sig

        require_relative "repositories_finder"
        require_relative "pom_fetcher"

        DOT_SEPARATOR_REGEX = %r{\.(?!\d+([.\/_\-]|$)+)}
        MAVEN_PROPERTY_REGEX = /\$\{.+?/

        sig do
          params(
            dependency_files: T::Array[DependencyFile],
            credentials: T::Array[Dependabot::Credential]
          )
            .void
        end
        def initialize(dependency_files:, credentials: [])
          @dependency_files = dependency_files
          @credentials = credentials
          @pom_fetcher = T.let(
            PomFetcher.new(dependency_files: dependency_files),
            Dependabot::Maven::FileParser::PomFetcher
          )
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig do
          params(
            property_name: String,
            callsite_pom: DependencyFile,
            seen_properties: T::Set[String]
          ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def property_details(property_name:, callsite_pom:, seen_properties: Set.new)
          pom = callsite_pom
          doc = Nokogiri::XML(pom.content)
          doc.remove_namespaces!

          # Loop through the paths that would satisfy this property name,
          # looking for one that exists in this POM
          nm = sanitize_property_name(property_name)
          node =
            loop do
              candidate_node =
                doc.xpath("/project/#{nm}").last ||
                doc.xpath("/project/properties/#{property_name}").last ||
                doc.xpath("/project/profiles/profile/properties/#{property_name}").last

              break candidate_node if candidate_node
              break unless nm.match?(DOT_SEPARATOR_REGEX)

              nm = nm.sub(DOT_SEPARATOR_REGEX, "/")
            rescue Nokogiri::XML::XPath::SyntaxError => e
              raise DependencyFileNotEvaluatable, e.message
            end

          if node.nil? && parent_pom(pom)
            return property_details(
              property_name: property_name,
              callsite_pom: T.must(parent_pom(pom)),
              seen_properties: seen_properties
            )
          end
          # If the property can’t be resolved for any reason, we return nil which
          # causes Dependabot to skip the dependency.
          # This differs from Maven’s behavior, where an unresolved property would fail the entire build.
          # We intentionally choose this as a compromise so Dependabot can continue parsing the rest of the project,
          # rather than failing completely due to a single unknown property.
          # The trade-off is that some dependencies may not be updated as expected.
          Dependabot.logger.warn "Could not resolve property '#{property_name}'" unless node
          return nil unless node

          content = node.content.strip

          # Detect infinite recursion such as ${property1} where property1=${property1}
          if seen_properties.include?(property_name)
            raise Dependabot::DependencyFileNotParseable.new(
              callsite_pom.name,
              "Error trying to resolve recursive expression '${#{property_name}}'."
            )
          end

          seen_properties << property_name

          # If the content has no placeholders, return it as-is
          return { file: pom.name, node: node, value: content } unless content.match?(MAVEN_PROPERTY_REGEX)

          resolve_property_placeholder(content, callsite_pom, pom, node, seen_properties)
        end
        # rubocop:enable Metrics/PerceivedComplexity

        private

        # Extract property placeholders from a string and resolve them
        # These properties can be simple properties such as ${project.version}
        # or more complex such as ${my.property.${other.property}} or constant.${property}
        # See https://maven.apache.org/pom.html#properties
        sig do
          params(
            content: String,
            callsite_pom: DependencyFile,
            pom: DependencyFile,
            node: T.untyped,
            seen_properties: T::Set[String]
          ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
        end
        def resolve_property_placeholder(content, callsite_pom, pom, node, seen_properties)
          resolved_value = content.gsub(/\$\{(.+?)}/) do
            inner_name = Regexp.last_match(1)
            resolved = property_details(
              property_name: T.must(inner_name),
              callsite_pom: callsite_pom,
              seen_properties: seen_properties
            )
            T.must(resolved)[:value]
          end

          { file: pom.name, node: node, value: resolved_value }
        end

        sig { returns(T::Array[DependencyFile]) }
        attr_reader :dependency_files

        sig { params(property_name: String).returns(String) }
        def sanitize_property_name(property_name)
          property_name.sub(/^pom\./, "").sub(/^project\./, "")
        end

        # rubocop:disable Metrics/PerceivedComplexity
        sig { params(pom: DependencyFile).returns(T.nilable(DependencyFile)) }
        def parent_pom(pom)
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

          @pom_fetcher.fetch_remote_parent_pom(group_id, artifact_id, version, parent_repository_urls(pom))
        end
        # rubocop:enable Metrics/PerceivedComplexity

        sig { params(pom: DependencyFile).returns(T::Array[String]) }
        def parent_repository_urls(pom)
          repositories_finder.repository_urls(
            pom: pom,
            exclude_inherited: true,
            exclude_snapshots: false
          )
        end

        sig { returns(RepositoriesFinder) }
        def repositories_finder
          @repositories_finder ||= T.let(
            Dependabot::Maven::FileParser::RepositoriesFinder.new(
              pom_fetcher: @pom_fetcher,
              dependency_files: dependency_files,
              credentials: @credentials,
              evaluate_properties: false
            ),
            T.nilable(Dependabot::Maven::FileParser::RepositoriesFinder)
          )
        end
      end
    end
  end
end
