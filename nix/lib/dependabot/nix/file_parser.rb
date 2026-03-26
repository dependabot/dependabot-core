# typed: strict
# frozen_string_literal: true

require "json"
require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/nix/package_manager"

module Dependabot
  module Nix
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      # Source types that are backed by git and can be updated via revision tracking
      SUPPORTED_SOURCE_TYPES = T.let(%w(github gitlab sourcehut git).freeze, T::Array[String])

      SUPPORTED_LOCK_VERSION = 7

      DEFAULT_HOSTS = T.let(
        {
          "github" => "github.com",
          "gitlab" => "gitlab.com",
          "sourcehut" => "git.sr.ht"
        }.freeze,
        T::Hash[String, String]
      )

      sig { override.returns(T::Array[Dependabot::Dependency]) }
      def parse
        lock_content = JSON.parse(T.must(flake_lock.content))

        lock_version = lock_content["version"]
        if lock_version != SUPPORTED_LOCK_VERSION
          Dependabot.logger.warn(
            "flake.lock version #{lock_version.inspect} differs from expected #{SUPPORTED_LOCK_VERSION}"
          )
        end

        root_name = lock_content.fetch("root", "root")
        nodes = lock_content.fetch("nodes", {})
        root_node = nodes.fetch(root_name, {})
        root_inputs = root_node.fetch("inputs", {})

        root_inputs.filter_map do |input_name, node_label|
          node = resolve_node(node_label, nodes)
          next unless node

          build_dependency(input_name, node)
        end
      end

      sig { returns(Ecosystem) }
      def ecosystem
        @ecosystem ||= T.let(
          Ecosystem.new(
            name: ECOSYSTEM,
            package_manager: package_manager
          ),
          T.nilable(Dependabot::Ecosystem)
        )
      end

      private

      # Resolves a node_label to its node in the lock file.
      # node_label is either a string (direct reference) or an array ("follows" path
      # that must be walked through nested inputs maps).
      sig do
        params(
          node_label: T.any(String, T::Array[String]),
          nodes: T::Hash[String, T.untyped]
        ).returns(T.nilable(T::Hash[String, T.untyped]))
      end
      def resolve_node(node_label, nodes)
        return nodes[node_label] unless node_label.is_a?(Array)
        return nil if node_label.empty?

        # Walk the "follows" path: e.g. ["nixpkgs", "flake-utils"] means
        # follow root -> nixpkgs node -> its inputs -> flake-utils
        resolved_label = resolve_follows_path(node_label, nodes)
        resolved_label ? nodes[resolved_label] : nil
      end

      # Walks a "follows" path through nested inputs to find the final node label.
      sig do
        params(
          path: T::Array[String],
          nodes: T::Hash[String, T.untyped]
        ).returns(T.nilable(String))
      end
      def resolve_follows_path(path, nodes)
        current_node_label = T.let(nil, T.nilable(String))

        path.each_with_index do |segment, index|
          # For the first segment, look up in the root's inputs via nodes directly
          target = if index.zero?
                     # The first segment references a top-level node by name
                     segment
                   else
                     # Subsequent segments look up inputs within the current node
                     node = nodes[T.must(current_node_label)]
                     return nil unless node.is_a?(Hash)

                     inputs = node.fetch("inputs", nil)
                     return nil unless inputs.is_a?(Hash)

                     label = inputs[segment]
                     return nil unless label.is_a?(String)

                     label
                   end

          current_node_label = target
        end

        current_node_label
      end

      sig do
        params(
          input_name: String,
          node: T::Hash[String, T.untyped]
        ).returns(T.nilable(Dependabot::Dependency))
      end
      def build_dependency(input_name, node)
        locked = node.fetch("locked", nil)
        original = node.fetch("original", nil)
        return unless locked && original

        source_type = locked.fetch("type", nil)
        return unless SUPPORTED_SOURCE_TYPES.include?(source_type)

        rev = locked.fetch("rev", nil)
        return unless rev

        url = build_url(locked)
        return unless url

        ref = original.fetch("ref", nil)

        Dependency.new(
          name: input_name,
          version: rev,
          package_manager: "nix",
          requirements: [{
            requirement: nil,
            file: "flake.lock",
            source: { type: "git", url: url, branch: ref, ref: ref },
            groups: []
          }]
        )
      end

      sig { params(locked: T::Hash[String, T.untyped]).returns(T.nilable(String)) }
      def build_url(locked)
        case locked["type"]
        when "github"
          host = locked["host"] || DEFAULT_HOSTS["github"]
          "https://#{host}/#{locked['owner']}/#{locked['repo']}"
        when "gitlab"
          host = locked["host"] || DEFAULT_HOSTS["gitlab"]
          "https://#{host}/#{locked['owner']}/#{locked['repo']}"
        when "sourcehut"
          host = locked["host"] || DEFAULT_HOSTS["sourcehut"]
          "https://#{host}/~#{locked['owner']}/#{locked['repo']}"
        when "git"
          locked["url"]
        end
      end

      sig { returns(Dependabot::DependencyFile) }
      def flake_lock
        @flake_lock ||=
          T.let(
            T.must(get_original_file("flake.lock")),
            T.nilable(Dependabot::DependencyFile)
          )
      end

      sig { override.void }
      def check_required_files
        %w(flake.nix flake.lock).each do |filename|
          raise "No #{filename}!" unless get_original_file(filename)
        end
      end

      sig { returns(Ecosystem::VersionManager) }
      def package_manager
        @package_manager ||= T.let(
          PackageManager.new(T.must(nix_version)),
          T.nilable(Dependabot::Nix::PackageManager)
        )
      end

      sig { returns(T.nilable(String)) }
      def nix_version
        @nix_version ||= T.let(
          begin
            version_output = SharedHelpers.run_shell_command("nix --version")
            version_output.match(/nix.*?(\d+\.\d+[\.\d]*)/)&.captures&.first || "0.0.0"
          rescue StandardError
            "0.0.0"
          end,
          T.nilable(String)
        )
      end
    end
  end
end

Dependabot::FileParsers.register("nix", Dependabot::Nix::FileParser)
