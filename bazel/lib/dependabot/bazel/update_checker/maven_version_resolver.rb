# typed: strict
# frozen_string_literal: true

require "nokogiri"
require "excon"
require "sorbet-runtime"
require "dependabot/shared_helpers"
require "dependabot/bazel/update_checker"

module Dependabot
  module Bazel
    class UpdateChecker < Dependabot::UpdateCheckers::Base
      class MavenVersionResolver
        extend T::Sig

        MAVEN_CENTRAL_URL = "https://repo1.maven.org/maven2"

        sig { params(dependency: Dependabot::Dependency).void }
        def initialize(dependency:)
          @dependency = dependency
          @group_id = T.let(nil, T.nilable(String))
          @artifact_id = T.let(nil, T.nilable(String))
          @group_id, @artifact_id = parse_dependency_name(dependency.name)
        end

        sig { returns(T.nilable(String)) }
        def latest_version
          versions = fetch_versions
          return nil if versions.empty?

          release_versions = versions.reject { |v| v.include?("SNAPSHOT") }
          return nil if release_versions.empty?

          release_versions.max_by { |v| version_sort_key(v) }
        end

        sig { returns(T::Array[String]) }
        def fetch_versions
          return [] unless @group_id && @artifact_id

          group_path = @group_id.tr(".", "/")
          metadata_url = "#{MAVEN_CENTRAL_URL}/#{group_path}/#{@artifact_id}/maven-metadata.xml"

          response = Excon.get(metadata_url, idempotent: true, **SharedHelpers.excon_defaults)
          return [] unless response.status == 200

          parse_maven_metadata(response.body)
        rescue Excon::Error => e
          Dependabot.logger.warn("Failed to fetch Maven versions for #{@group_id}:#{@artifact_id}: #{e.message}")
          []
        end

        private

        sig { params(name: String).returns([T.nilable(String), T.nilable(String)]) }
        def parse_dependency_name(name)
          parts = name.split(":")
          return [nil, nil] unless parts.length >= 2

          [parts[0], parts[1]]
        end

        sig { params(xml: String).returns(T::Array[String]) }
        def parse_maven_metadata(xml)
          doc = Nokogiri::XML(xml)
          doc.remove_namespaces!
          doc.xpath("//version").map(&:text)
        rescue Nokogiri::XML::SyntaxError => e
          Dependabot.logger.warn("Failed to parse Maven metadata XML: #{e.message}")
          []
        end

        sig { params(version: String).returns(T::Array[T.any(Integer, String)]) }
        def version_sort_key(version)
          parts = version.split(/[.\-]/)

          parts.map do |part|
            case part
            when /^\d+$/
              part.to_i
            when /^alpha/i
              -3
            when /^beta/i
              -2
            when /^rc/i
              -1
            else
              0
            end
          end
        end
      end
    end
  end
end
