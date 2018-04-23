# frozen_string_literal: true

require "nokogiri"

require "dependabot/dependency_file"
require "dependabot/file_parsers/java/maven"
require "dependabot/shared_helpers"

# For documentation, see:
# - http://maven.apache.org/pom.html#Repositories
# - http://maven.apache.org/guides/mini/guide-multiple-repositories.html
module Dependabot
  module FileParsers
    module Java
      class Maven
        class RepositoriesFinder
          # In theory we should check the artifact type and either look in
          # <repositories> or <pluginRepositories>. In practice it's unlikely
          # anyone makes this distinction.
          REPOSITORY_SELECTOR = "repositories > repository, "\
                                "pluginRepositories > pluginRepository"

          # The Central Repository is included in the Super POM, which is
          # always inherited from.
          CENTRAL_REPO_URL = "https://repo.maven.apache.org/maven2"

          def initialize(dependency_files:)
            @dependency_files = dependency_files
          end

          # Collect all repository URLs from this POM and its parents
          def repository_urls(pom:, exclude_inherited: false)
            repo_urls_in_pom =
              Nokogiri::XML(pom.content).
              css(REPOSITORY_SELECTOR).
              map { |node| node.at_css("url").content.strip.gsub(%r{/$}, "") }

            return repo_urls_in_pom + [CENTRAL_REPO_URL] if exclude_inherited

            unless (parent = parent_pom(pom, repo_urls_in_pom))
              return repo_urls_in_pom + [CENTRAL_REPO_URL]
            end

            repo_urls_in_pom + repository_urls(pom: parent)
          end

          private

          attr_reader :dependency_files

          def pomfiles
            @pomfiles ||=
              dependency_files.select { |f| f.name.end_with?("pom.xml") }
          end

          def parent_pom(pom, repo_urls)
            doc = Nokogiri::XML(pom.content)
            doc.remove_namespaces!
            group_id = doc.at_xpath("//parent/groupId")&.content&.strip
            artifact_id = doc.at_xpath("//parent/artifactId")&.content&.strip
            version = doc.at_xpath("//parent/version")&.content&.strip

            return unless group_id && artifact_id
            name = [group_id, artifact_id].join(":")

            if internal_dependency_poms[name]
              return internal_dependency_poms[name]
            end

            fetch_remote_parent_pom(group_id, artifact_id, version, repo_urls)
          end

          def internal_dependency_poms
            return @internal_dependency_poms if @internal_dependency_poms

            @internal_dependency_poms = {}
            pomfiles.each do |pom|
              doc = Nokogiri::XML(pom.content)
              group_id    = doc.at_css("project > groupId") ||
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
                middlewares: SharedHelpers.excon_middleware
              )
              next unless @maven_responses[url].status == 200
              next unless pom?(@maven_responses[url].body)

              dependency_file = DependencyFile.new(
                name: "remote_pom.xml",
                content: @maven_responses[url].body
              )

              return dependency_file
            end

            # If a parent POM couldn't be found, return `nil`
            nil
          end

          def remote_pom_url(group_id, artifact_id, version, base_repo_url)
            "#{base_repo_url}/"\
            "#{group_id.tr('.', '/')}/#{artifact_id}/#{version}/"\
            "#{artifact_id}-#{version}.pom"
          end

          def pom?(content)
            !Nokogiri::XML(content).at_css("project > artifactId").nil?
          end
        end
      end
    end
  end
end
