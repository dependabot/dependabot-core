# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/manifest_sets"
require "dependabot/manifest_sets/descriptor"
require "dependabot/manifest_sets/directory_listing"
require "dependabot/manifest_sets/inputs"

module Dependabot
  module ManifestSets
    # Builds the input list a job reports for its directory.
    module Collector
      extend T::Sig

      # The grapher's original inputs, plus every owner-selection file present directly in the directory
      # for every owner of the job's ecosystem, whether or not this job read it. Owner selection over the
      # reported list therefore gives the same answer whichever package manager's job produced it. Jobs
      # whose package manager is not a catalog owner report only the grapher's inputs.
      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile],
          repo_contents_path: T.nilable(String),
          commit: String,
          directory: String,
          owner_id: String,
          catalog: Catalog
        ).returns(Inputs)
      end
      def self.collect(
        dependency_files:,
        repo_contents_path:,
        commit:,
        directory:,
        owner_id:,
        catalog: ManifestSets.catalog
      )
        inputs = Inputs.resolve(dependency_files:, repo_contents_path:, commit:)
        ecosystem = catalog.ecosystem_for_owner(owner_id)
        return inputs if !inputs.resolved? || ecosystem.nil?

        set_directory = DirectoryListing.normalize(directory)
        listing = set_directory && DirectoryListing.read(
          repo_contents_path: T.must(repo_contents_path),
          commit: commit,
          directory: set_directory
        )
        return Inputs.unresolvable(Inputs::UNKNOWN_PROVENANCE) if listing.nil?

        inputs.with_files(selector_files(ecosystem, listing))
      end

      # The descriptor a job reports for its directory, or nil when it must report none: the job's package
      # manager is not a catalog owner, or its result is empty while files matching the ecosystem's path rules
      # remain in the directory (another owner's set). `unresolvable_reason` is the grapher's own reason why
      # the set's inputs cannot be listed. An empty result is `absent` only when no file directly in the
      # directory matches a path rule, which includes a directory that no longer exists at the commit.
      sig do
        params(
          dependency_files: T::Array[Dependabot::DependencyFile],
          repo_contents_path: T.nilable(String),
          commit: String,
          directory: String,
          owner_id: String,
          graph_version: String,
          unresolvable_reason: T.nilable(String),
          catalog: Catalog
        ).returns(T.nilable(Descriptor))
      end
      def self.describe( # rubocop:disable Metrics/AbcSize,Metrics/PerceivedComplexity
        dependency_files:,
        repo_contents_path:,
        commit:,
        directory:,
        owner_id:,
        graph_version:,
        unresolvable_reason: nil,
        catalog: ManifestSets.catalog
      )
        ecosystem = catalog.ecosystem_for_owner(owner_id)
        set_directory = DirectoryListing.normalize(directory)
        return nil if ecosystem.nil? || set_directory.nil?

        identity = { ecosystem: ecosystem.id, directory: set_directory, owner: owner_id, graph_version: }
        return Descriptor.unresolvable(**identity, reason: unresolvable_reason) if unresolvable_reason

        inputs = Inputs.resolve(dependency_files:, repo_contents_path:, commit:)
        return Descriptor.unresolvable(**identity, reason: T.must(inputs.unresolvable_reason)) unless inputs.resolved?

        listing = DirectoryListing.read(
          repo_contents_path: T.must(repo_contents_path),
          commit:,
          directory: set_directory
        )
        return Descriptor.unresolvable(**identity, reason: Descriptor::UNKNOWN_PROVENANCE) if listing.nil?

        if inputs.files.empty?
          return nil if listing.blobs.keys.any? { |basename| ecosystem.rule_matches?(basename) }

          return Descriptor.absent(**identity)
        end

        inputs = inputs.with_files(selector_files(ecosystem, listing))
        return Descriptor.unresolvable(**identity, reason: T.must(inputs.unresolvable_reason)) unless inputs.resolved?

        prefix = set_directory == "." ? "" : "#{set_directory}/"
        basenames = inputs.files.filter_map do |file|
          basename = file.path.delete_prefix(prefix)
          basename if file.path.start_with?(prefix) && !basename.include?("/")
        end
        if ecosystem.select_owner(basenames).ambiguous
          return Descriptor.unresolvable(**identity, reason: Descriptor::AMBIGUOUS_OWNER)
        end

        Descriptor.present(**identity, files: inputs.files)
      end

      sig { params(ecosystem: Catalog::Ecosystem, listing: DirectoryListing).returns(T::Array[InputFile]) }
      def self.selector_files(ecosystem, listing)
        prefix = listing.directory == "." ? "" : "#{listing.directory}/"
        ecosystem.selector_basenames.filter_map do |basename|
          oid = listing.blobs[basename]
          InputFile.new(path: "#{prefix}#{basename}", blob_oid: oid) if oid
        end
      end
      private_class_method :selector_files
    end
  end
end
