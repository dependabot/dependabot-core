# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/gradle/distributions"
require "dependabot/gradle/file_fetcher"
require "dependabot/gradle/file_parser/repositories_finder"
require "dependabot/maven/shared/shared_metadata_finder"
require "dependabot/metadata_finders"

module Dependabot
  module Gradle
    class MetadataFinder < Dependabot::Maven::Shared::SharedMetadataFinder
      extend T::Sig

      KOTLIN_PLUGIN_REPO_PREFIX = "org.jetbrains.kotlin"

      private

      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        return distributions_source if Distributions.distribution_requirements?(dependency.requirements)

        super
      end

      # The Gradle Wrapper does not have its own release notes.
      # Instead, it shares the release notes of the matching Gradle version.
      sig { returns(Dependabot::Source) }
      def distributions_source
        Source.new(
          provider: "github",
          repo: "gradle/gradle",
          directory: "/"
        )
      end

      sig { override.returns(T.class_of(Dependabot::FileFetchers::Base)) }
      def file_fetcher_class
        Dependabot::Gradle::FileFetcher
      end

      sig { override.returns(T.nilable(String)) }
      def dependency_artifact_id
        if kotlin_plugin? then "#{KOTLIN_PLUGIN_REPO_PREFIX}.#{dependency.name}.gradle.plugin"
        elsif plugin? then "#{dependency.name}.gradle.plugin"
        else
          dependency.name.split(":").last
        end
      end

      sig { override.returns(String) }
      def maven_repo_dependency_url
        group_id, artifact_id =
          if kotlin_plugin?
            ["#{KOTLIN_PLUGIN_REPO_PREFIX}.#{dependency.name}",
             "#{KOTLIN_PLUGIN_REPO_PREFIX}.#{dependency.name}.gradle.plugin"]
          elsif plugin? then [dependency.name, "#{dependency.name}.gradle.plugin"]
          else
            dependency.name.split(":")
          end

        "#{maven_repo_url}/#{group_id&.tr('.', '/')}/#{artifact_id}"
      end

      sig { override.returns(String) }
      def maven_repo_url
        source = dependency.requirements
                           .find { |r| r.fetch(:source) }&.fetch(:source)

        source&.fetch(:url, nil) ||
          source&.fetch("url") ||
          Gradle::FileParser::RepositoriesFinder::CENTRAL_REPO_URL
      end

      sig { override.returns(String) }
      def central_repo_url
        Gradle::FileParser::RepositoriesFinder::CENTRAL_REPO_URL
      end

      sig { returns(T::Boolean) }
      def plugin?
        dependency.requirements.any? { |r| r.fetch(:groups).include? "plugins" }
      end

      sig { returns(T::Boolean) }
      def kotlin_plugin?
        plugin? && dependency.requirements.any? { |r| r.fetch(:groups).include? "kotlin" }
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("gradle", Dependabot::Gradle::MetadataFinder)
