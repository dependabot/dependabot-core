# typed: strong
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
        return Inputs.unresolvable(Inputs::UNKNOWN_PROVENANCE) if listing.nil? || symlinked_selector?(
          ecosystem,
          listing
        )

        inputs.with_files(selector_files(ecosystem, listing))
      end

      # The descriptor a job reports for its directory, or nil when it must report none: the job's package
      # manager is not a catalog owner, or its result is empty while files matching the ecosystem's path rules
      # remain in the directory (another owner's set). `unresolvable_reason` is the grapher's own reason why
      # the set's inputs cannot be listed. An empty result is `absent` only when no file directly in the
      # directory matches a path rule, which includes a directory that no longer exists at the commit. Nonempty
      # inputs in a directory where no such file exists are unresolvable: the catalog describes no set there.
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
        if listing.nil? || symlinked_selector?(ecosystem, listing)
          return Descriptor.unresolvable(**identity, reason: Descriptor::UNKNOWN_PROVENANCE)
        end

        if inputs.files.empty?
          return nil if holds_set?(ecosystem, listing)

          return Descriptor.absent(**identity)
        end
        unless holds_set?(ecosystem, listing)
          return Descriptor.unresolvable(**identity, reason: Descriptor::UNKNOWN_PROVENANCE)
        end

        inputs = inputs.with_files(selector_files(ecosystem, listing))
        return Descriptor.unresolvable(**identity, reason: T.must(inputs.unresolvable_reason)) unless inputs.resolved?

        if ecosystem.select_owner(basenames_in(set_directory, inputs.files)).ambiguous
          return Descriptor.unresolvable(**identity, reason: Descriptor::AMBIGUOUS_OWNER)
        end

        Descriptor.present(**identity, files: inputs.files)
      end

      sig { params(directory: String, files: T::Array[InputFile]).returns(T::Array[String]) }
      def self.basenames_in(directory, files)
        prefix = directory == "." ? "" : "#{directory}/"
        files.filter_map do |file|
          basename = file.path.delete_prefix(prefix)
          basename if file.path.start_with?(prefix) && !basename.include?("/")
        end
      end

      # Whether any file directly in the directory, a blob or a symlink, matches one of the ecosystem's path rules.
      sig { params(ecosystem: Catalog::Ecosystem, listing: DirectoryListing).returns(T::Boolean) }
      def self.holds_set?(ecosystem, listing)
        (listing.blobs.keys + listing.symlinks).any? { |basename| ecosystem.rule_matches?(basename) }
      end

      # Like a symlinked input, a symlinked selector's link text says nothing about what it points to.
      sig { params(ecosystem: Catalog::Ecosystem, listing: DirectoryListing).returns(T::Boolean) }
      def self.symlinked_selector?(ecosystem, listing)
        listing.symlinks.intersect?(ecosystem.selector_basenames)
      end

      sig { params(ecosystem: Catalog::Ecosystem, listing: DirectoryListing).returns(T::Array[InputFile]) }
      def self.selector_files(ecosystem, listing)
        prefix = listing.directory == "." ? "" : "#{listing.directory}/"
        ecosystem.selector_basenames.filter_map do |basename|
          oid = listing.blobs[basename]
          InputFile.new(path: "#{prefix}#{basename}", blob_oid: oid) if oid
        end
      end
      private_class_method :selector_files, :holds_set?, :symlinked_selector?, :basenames_in
    end
  end
end
