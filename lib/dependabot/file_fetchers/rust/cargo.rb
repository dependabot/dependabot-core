# frozen_string_literal: true

require "toml-rb"

require "dependabot/file_fetchers/base"
require "dependabot/file_parsers/rust/cargo"

# Docs on Cargo workspaces:
# https://doc.rust-lang.org/cargo/reference/manifest.html#the-workspace-section
module Dependabot
  module FileFetchers
    module Rust
      class Cargo < Dependabot::FileFetchers::Base
        def self.required_files_in?(filenames)
          filenames.include?("Cargo.toml")
        end

        def self.required_files_message
          "Repo must contain a Cargo.toml."
        end

        private

        def fetch_files
          fetched_files = []
          fetched_files << cargo_toml
          fetched_files << cargo_lock if cargo_lock
          fetched_files += workspace_and_path_dependency_files
          fetched_files
        end

        def workspace_and_path_dependency_files
          @workspace_and_path_dependency_files ||=
            fetch_workspace_and_path_dependency_files(
              file: cargo_toml,
              previously_fetched_files: []
            )
        end

        def fetch_workspace_and_path_dependency_files(
          file:,
          previously_fetched_files:
        )
          current_dir = file.name.split("/")[0..-2].join("/")
          current_dir = nil if current_dir == ""

          path_dep_and_workspace_paths_from_file(file).flat_map do |path|
            path = File.join(current_dir, path) unless current_dir.nil?
            path = Pathname.new(path).cleanpath.to_path

            next if previously_fetched_files.map(&:name).include?(path)
            next if file.name == path

            fetched_file = fetch_file_from_host(path)
            previously_fetched_files << fetched_file
            grandchild_requirement_files =
              fetch_workspace_and_path_dependency_files(
                file: fetched_file,
                previously_fetched_files: previously_fetched_files
              )
            [fetched_file, *grandchild_requirement_files]
          end.compact
        end

        def path_dep_and_workspace_paths_from_file(file)
          [
            *path_dependency_paths_from_file(file),
            *workspace_dependency_paths_from_file(file)
          ].uniq
        end

        def path_dependency_paths_from_file(file)
          FileParsers::Rust::Cargo::DEPENDENCY_TYPES.flat_map do |type|
            parsed_file(file).fetch(type, {}).map do |_, details|
              next unless details.is_a?(Hash)
              next unless details["path"]
              File.join(details["path"], "Cargo.toml")
            end
          end.compact
        end

        def workspace_dependency_paths_from_file(file)
          workspace_paths = parsed_file(file).dig("workspace", "members")
          return [] unless workspace_paths&.any?

          # Expand any workspace paths that specify a `*`
          workspace_paths = workspace_paths.flat_map do |path|
            path.end_with?("*") ? expand_workspaces(path) : [path]
          end

          # Excluded paths, to be subtracted for the workspaces array
          excluded_paths = parsed_file(file).dig("workspace", "excluded_paths")

          (workspace_paths - (excluded_paths || [])).map do |path|
            File.join(path, "Cargo.toml")
          end
        end

        def expand_workspaces(path)
          dir = directory.gsub(%r{(^/|/$)}, "")
          repo_contents(dir: path.gsub(/\*$/, "")).
            select { |file| file.type == "dir" }.
            map { |f| f.path.gsub(%r{^/?#{Regexp.escape(dir)}/?}, "") }
        end

        def parsed_file(file)
          TomlRB.parse(file.content)
        rescue TomlRB::ParseError
          raise Dependabot::DependencyFileNotParseable, file.path
        end

        def cargo_toml
          @cargo_toml ||= fetch_file_from_host("Cargo.toml")
        end

        def cargo_lock
          @cargo_lock ||= fetch_file_if_present("Cargo.lock")
        end
      end
    end
  end
end
