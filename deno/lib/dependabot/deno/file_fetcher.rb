# typed: strict
# frozen_string_literal: true

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/deno/helpers"

module Dependabot
  module Deno
    class FileFetcher < Dependabot::FileFetchers::Base
      extend T::Sig

      MANIFEST_FILENAMES = T.let(%w(deno.json deno.jsonc).freeze, T::Array[String])

      sig { override.returns(String) }
      def self.required_files_message
        "Repo must contain a deno.json or deno.jsonc."
      end

      sig { override.params(filenames: T::Array[String]).returns(T::Boolean) }
      def self.required_files_in?(filenames)
        filenames.any? { |f| MANIFEST_FILENAMES.include?(f) }
      end

      sig { override.returns(T::Array[DependencyFile]) }
      def fetch_files
        fetched_files = []
        fetched_files << manifest_file
        fetched_files.concat(workspace_member_files)
        fetched_files << lockfile if lockfile
        fetched_files.uniq(&:name)
      end

      sig { override.returns(T.nilable(T::Hash[Symbol, T.anything])) }
      def ecosystem_versions
        nil
      end

      private

      sig { returns(DependencyFile) }
      def manifest_file
        @manifest_file ||= T.let(
          begin
            file = MANIFEST_FILENAMES.filter_map { |f| fetch_file_if_present(f) }.first
            raise Dependabot::DependencyFileNotFound.new(nil, self.class.required_files_message) unless file

            file
          end,
          T.nilable(DependencyFile)
        )
      end

      sig { returns(T.nilable(DependencyFile)) }
      def lockfile
        @lockfile ||= T.let(
          fetch_file_if_present("deno.lock"),
          T.nilable(DependencyFile)
        )
      end

      # Fetches the deno.json/deno.jsonc of every workspace member declared in the
      # root manifest's "workspace" field. Members with neither file (e.g.
      # package.json-only members) are skipped.
      sig { returns(T::Array[DependencyFile]) }
      def workspace_member_files
        @workspace_member_files ||= T.let(
          workspace_member_dirs.filter_map { |dir| fetch_member_manifest(dir) },
          T.nilable(T::Array[DependencyFile])
        )
      end

      sig { params(dir: String).returns(T.nilable(DependencyFile)) }
      def fetch_member_manifest(dir)
        MANIFEST_FILENAMES.filter_map { |f| fetch_file_if_present(File.join(dir, f)) }.first
      end

      # Resolves the "workspace" field into a concrete list of member directory
      # paths (relative to the repo directory), expanding glob patterns and
      # applying "!" negations. Supports both the array form (["./a", "./b"]) and
      # the legacy object form ({ "members": [...] }).
      sig { returns(T::Array[String]) }
      def workspace_member_dirs
        members = workspace_members
        return [] if members.empty?

        includes, excludes = members.partition { |m| !m.start_with?("!") }
        excluded = excludes.flat_map { |m| expand_member(m.delete_prefix("!")) }

        includes
          .flat_map { |m| expand_member(m) }
          .uniq
          .reject { |dir| excluded.include?(dir) }
          # Member paths come from manifest content; never fetch from an absolute
          # path or one that traverses out of the repo via "..".
          .select { |dir| Helpers.safe_relative_path?(dir) }
      end

      sig { returns(T::Array[String]) }
      def workspace_members
        workspace = Helpers.parse_json_or_jsonc(manifest_file.content).fetch("workspace", nil)

        case workspace
        when Array then workspace.map(&:to_s)
        when Hash then Array(workspace["members"]).map(&:to_s)
        else []
        end
      end

      # Expands a single member entry to directory paths. Plain paths are
      # normalised; glob entries (containing "*") are matched against the repo
      # tree, honouring Deno's literal depth semantics (each "/*" = one level).
      sig { params(member: String).returns(T::Array[String]) }
      def expand_member(member)
        normalised = normalise_member_path(member)
        return [normalised] unless normalised.include?("*")

        expand_glob(normalised)
      end

      sig { params(member: String).returns(String) }
      def normalise_member_path(member)
        member.delete_prefix("./").delete_suffix("/")
      end

      # Expands a glob like "packages/*" or "examples/*/*" by walking the repo one
      # directory level per "*" segment. Only directories are kept.
      sig { params(pattern: String).returns(T::Array[String]) }
      def expand_glob(pattern)
        segments = pattern.split("/")
        dirs = T.let([""], T::Array[String])

        segments.each do |segment|
          dirs = dirs.flat_map do |base|
            if segment == "*"
              child_directories(base)
            else
              child = base.empty? ? segment : File.join(base, segment)
              [child]
            end
          end
        end

        dirs.reject(&:empty?)
      end

      sig { params(dir: String).returns(T::Array[String]) }
      def child_directories(dir)
        contents = repo_contents(dir: dir.empty? ? "." : dir, raise_errors: false)
        contents.select { |entry| entry.type == "dir" }
                .map { |entry| dir.empty? ? entry.name : File.join(dir, entry.name) }
      rescue Dependabot::DependencyFileNotFound, Dependabot::DirectoryNotFound
        []
      end
    end
  end
end

Dependabot::FileFetchers.register("deno", Dependabot::Deno::FileFetcher)
