# frozen_string_literal: true

require "pathname"
require "toml-rb"

require "dependabot/file_fetchers"
require "dependabot/file_fetchers/base"
require "dependabot/cargo/file_parser"

# Docs on Cargo workspaces:
# https://doc.rust-lang.org/cargo/reference/manifest.html#the-workspace-section
module Dependabot
  module Cargo
    class FileFetcher < Dependabot::FileFetchers::Base
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
        fetched_files << rust_toolchain if rust_toolchain
        fetched_files += fetch_path_dependency_and_workspace_files
        fetched_files.uniq
      end

      def fetch_path_dependency_and_workspace_files(files = nil)
        fetched_files = files || [cargo_toml]

        fetched_files += path_dependency_files(fetched_files)
        fetched_files += fetched_files.flat_map { |f| workspace_files(f) }

        updated_files = fetched_files.reject(&:support_file?).uniq
        updated_files +=
          fetched_files.uniq.
          reject { |f| updated_files.map(&:name).include?(f.name) }

        return updated_files if updated_files == files

        fetch_path_dependency_and_workspace_files(updated_files)
      end

      def workspace_files(cargo_toml)
        @workspace_files ||= {}
        @workspace_files[cargo_toml.name] ||=
          fetch_workspace_files(
            file: cargo_toml,
            previously_fetched_files: []
          )
      end

      def path_dependency_files(fetched_files)
        @path_dependency_files ||= {}
        fetched_path_dependency_files = []
        fetched_files.each do |file|
          @path_dependency_files[file.name] ||=
            fetch_path_dependency_files(
              file: file,
              previously_fetched_files: fetched_files +
                                        fetched_path_dependency_files
            )

          fetched_path_dependency_files += @path_dependency_files[file.name]
        end

        fetched_path_dependency_files
      end

      def fetch_workspace_files(file:, previously_fetched_files:)
        current_dir = file.name.split("/")[0..-2].join("/")
        current_dir = nil if current_dir == ""

        files = workspace_dependency_paths_from_file(file).flat_map do |path|
          path = File.join(current_dir, path) unless current_dir.nil?
          path = Pathname.new(path).cleanpath.to_path

          next if previously_fetched_files.map(&:name).include?(path)
          next if file.name == path

          fetched_file = fetch_file_from_host(path)
          previously_fetched_files << fetched_file
          grandchild_requirement_files =
            fetch_workspace_files(
              file: fetched_file,
              previously_fetched_files: previously_fetched_files
            )
          [fetched_file, *grandchild_requirement_files]
        end.compact

        files.each { |f| f.support_file = file != cargo_toml }
        files
      end

      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def fetch_path_dependency_files(file:, previously_fetched_files:)
        current_dir = file.name.split("/")[0..-2].join("/")
        current_dir = nil if current_dir == ""
        unfetchable_required_path_deps = []

        path_dependency_files ||=
          path_dependency_paths_from_file(file).flat_map do |path|
            path = File.join(current_dir, path) unless current_dir.nil?
            path = Pathname.new(path).cleanpath.to_path

            next if previously_fetched_files.map(&:name).include?(path)
            next if file.name == path

            fetched_file = fetch_file_from_host(path, fetch_submodules: true).
                           tap { |f| f.support_file = true }
            previously_fetched_files << fetched_file
            grandchild_requirement_files =
              fetch_path_dependency_files(
                file: fetched_file,
                previously_fetched_files: previously_fetched_files
              )
            [fetched_file, *grandchild_requirement_files]
          rescue Dependabot::DependencyFileNotFound
            next unless required_path?(file, path)

            unfetchable_required_path_deps << path
          end.compact

        return path_dependency_files if unfetchable_required_path_deps.none?

        raise Dependabot::PathDependenciesNotReachable,
              unfetchable_required_path_deps
      end
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity

      def path_dependency_paths_from_file(file)
        paths = []

        # Paths specified in dependency declaration
        Cargo::FileParser::DEPENDENCY_TYPES.each do |type|
          parsed_file(file).fetch(type, {}).each do |_, details|
            next unless details.is_a?(Hash)
            next unless details["path"]

            paths << File.join(details["path"], "Cargo.toml")
          end
        end

        # Paths specified for target-specific dependencies
        parsed_file(file).fetch("target", {}).each do |_, t_details|
          Cargo::FileParser::DEPENDENCY_TYPES.each do |type|
            t_details.fetch(type, {}).each do |_, details|
              next unless details.is_a?(Hash)
              next unless details["path"]

              paths << File.join(details["path"], "Cargo.toml")
            end
          end
        end

        # Paths specified as replacements
        parsed_file(file).fetch("replace", {}).each do |_, details|
          next unless details.is_a?(Hash)
          next unless details["path"]

          paths << File.join(details["path"], "Cargo.toml")
        end

        paths
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

      # Check whether a path is required or not. It will not be required if
      # an alternative source (i.e., a git source) is also specified
      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      def required_path?(file, path)
        # Paths specified in dependency declaration
        Cargo::FileParser::DEPENDENCY_TYPES.each do |type|
          parsed_file(file).fetch(type, {}).each do |_, details|
            next unless details.is_a?(Hash)
            next unless details["path"]
            next unless path == File.join(details["path"], "Cargo.toml")

            return true if details["git"].nil?
          end
        end

        # Paths specified for target-specific dependencies
        parsed_file(file).fetch("target", {}).each do |_, t_details|
          Cargo::FileParser::DEPENDENCY_TYPES.each do |type|
            t_details.fetch(type, {}).each do |_, details|
              next unless details.is_a?(Hash)
              next unless details["path"]
              next unless path == File.join(details["path"], "Cargo.toml")

              return true if details["git"].nil?
            end
          end
        end

        # Paths specified as replacements
        parsed_file(file).fetch("replace", {}).each do |_, details|
          next unless details.is_a?(Hash)
          next unless details["path"]
          next unless path == File.join(details["path"], "Cargo.toml")

          return true if details["git"].nil?
        end

        false
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity

      def expand_workspaces(path)
        path = Pathname.new(path).cleanpath.to_path
        dir = directory.gsub(%r{(^/|/$)}, "")
        unglobbed_path = path.split("*").first.gsub(%r{(?<=/)[^/]*$}, "")

        repo_contents(dir: unglobbed_path, raise_errors: false).
          select { |file| file.type == "dir" }.
          map { |f| f.path.gsub(%r{^/?#{Regexp.escape(dir)}/?}, "") }.
          select { |filename| File.fnmatch?(path, filename) }
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

      def rust_toolchain
        @rust_toolchain ||= fetch_file_if_present("rust-toolchain")&.
                            tap { |f| f.support_file = true }
      end
    end
  end
end

Dependabot::FileFetchers.register("cargo", Dependabot::Cargo::FileFetcher)
