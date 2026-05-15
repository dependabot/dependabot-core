# typed: strict
# frozen_string_literal: true

require "dependabot/metadata_finders"
require "dependabot/metadata_finders/base"
require "dependabot/shared_helpers"
require "sorbet-runtime"

module Dependabot
  module Docker
    class MetadataFinder < Dependabot::MetadataFinders::Base
      extend T::Sig

      private

      # Finds the repository for the Docker image using OCI annotations.
      # @see https://specs.opencontainers.org/image-spec/annotations/
      sig { override.returns(T.nilable(Dependabot::Source)) }
      def look_up_source
        return if dependency.requirements.empty?

        new_source = dependency.requirements.first&.fetch(:source)
        return unless new_source && new_source[:registry] && (new_source[:tag] || new_source[:digest])

        details = image_details(new_source)
        image_source = details.dig("config", "Labels", "org.opencontainers.image.source")
        # Return early if the org.opencontainers.image.source label is not present
        return unless image_source

        # If we have a tag, return the source directly without additional version metadata
        return Dependabot::Source.from_url(image_source) if new_source[:tag]

        # If we only have a digest, we need to look for the version label to build the source
        build_source_from_image_version(image_source, details)
      rescue StandardError => e
        Dependabot.logger.warn("Error looking up Docker source: #{e.message}")
        nil
      end

      sig do
        params(
          source: T::Hash[Symbol, T.untyped]
        ).returns(
          T::Hash[String, T.untyped]
        )
      end
      def image_details(source)
        registry = source[:registry]
        tag = source[:tag]
        digest = source[:digest]

        image_ref =
          # If both tag and digest are present, use the digest as docker ignores the tag when a digest is present
          if digest
            "#{registry}/#{dependency.name}@sha256:#{digest}"
          else
            "#{registry}/#{dependency.name}:#{tag}"
          end

        Dependabot.logger.info("Looking up Docker source #{image_ref}")
        output = SharedHelpers.run_shell_command("regctl image inspect #{image_ref}")
        JSON.parse(output)
      end

      # Builds a Dependabot::Source object using the OCI image version label.
      #
      # This is used as a fallback when an image is referenced by digest rather than a tag
      sig do
        params(
          image_source: String,
          details: T::Hash[String, T.untyped]
        ).returns(T.nilable(Dependabot::Source))
      end
      def build_source_from_image_version(image_source, details)
        image_version = details.dig("config", "Labels", "org.opencontainers.image.version")
        revision = details.dig("config", "Labels", "org.opencontainers.image.revision")
        # Sometimes the versions are not tags (e.g., "24.04")
        # We only want to build a source if the version looks like a tag (starts with "v")
        # This is a safeguard for a first iteration. We may adjust this later based on user feedback.
        tag_like = image_version&.start_with?("v")

        return unless tag_like || revision

        parsed_source = Dependabot::Source.from_url(image_source)
        return unless parsed_source

        branch_info = image_version ? "image version '#{image_version}'" : "unknown image version"
        commit_info = revision ? "revision '#{revision}'" : "no commit"
        Dependabot.logger.info "Building source with #{branch_info} and #{commit_info}"

        Dependabot::Source.new(
          provider: parsed_source.provider,
          repo: parsed_source.repo,
          directory: parsed_source.directory,
          branch: image_version,
          commit: revision
        )
      end
    end
  end
end

Dependabot::MetadataFinders
  .register("docker", Dependabot::Docker::MetadataFinder)
