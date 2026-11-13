# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency_file"
require "dependabot/manifest_sets"
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

        selector_basenames = ecosystem.selector_basenames
        # Like a symlinked input, a symlinked selector's link text says nothing about what it points to.
        return Inputs.unresolvable(Inputs::UNKNOWN_PROVENANCE) if listing.symlinks.intersect?(selector_basenames)

        prefix = listing.directory == "." ? "" : "#{listing.directory}/"
        selectors = selector_basenames.filter_map do |basename|
          oid = listing.blobs[basename]
          InputFile.new(path: "#{prefix}#{basename}", blob_oid: oid) if oid
        end
        inputs.with_files(selectors)
      end
    end
  end
end
