# typed: strict
# frozen_string_literal: true

require "uri"
require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/file_parsers"
require "dependabot/file_parsers/base"
require "dependabot/shared_helpers"
require "dependabot/nix/channel"
require "dependabot/nix/lockfile"
require "dependabot/nix/package_manager"

module Dependabot
  module Nix
    class FileParser < Dependabot::FileParsers::Base
      extend T::Sig

      # Updatable source types: git-backed sources plus NixOS channel tarballs.
      SUPPORTED_SOURCE_TYPES = %w(github gitlab sourcehut git tarball).freeze

      SUPPORTED_LOCK_VERSION = 7

      # Where the registry resolves an indirect channel input to: a NixOS release tarball.
      RELEASE_TARBALL_HOSTS = %w(releases.nixos.org channels.nixos.org).freeze
      RELEASE_TARBALL_PATH = %r{/nixexprs\.tar\.(?<extension>xz|gz|bz2|zst)\z}

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
        lockfile = Lockfile.new(T.must(flake_lock.content))

        lock_version = lockfile.version
        if lock_version != SUPPORTED_LOCK_VERSION
          Dependabot.logger.warn(
            "flake.lock version #{lock_version.inspect} differs from expected #{SUPPORTED_LOCK_VERSION}"
          )
        end

        lockfile.root_input_names.filter_map do |input_name|
          node = lockfile.input_node(input_name)
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

        # Skip inputs pinned to a bare commit SHA: no branch or tag to track.
        return if revision_pinned?(original)

        rev = locked.fetch("rev", nil)
        return unless rev

        if source_type == "tarball"
          build_tarball_dependency(input_name, locked, original, rev)
        else
          build_git_dependency(input_name, locked, original, rev)
        end
      end

      sig do
        params(
          input_name: String,
          locked: T::Hash[String, T.untyped],
          original: T::Hash[String, T.untyped],
          rev: String
        ).returns(T.nilable(Dependabot::Dependency))
      end
      def build_git_dependency(input_name, locked, original, rev)
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
            source: { type: "git", url: url, branch: nil, ref: ref },
            groups: []
          }]
        )
      end

      sig { params(original: T::Hash[String, T.untyped]).returns(T::Boolean) }
      def revision_pinned?(original)
        !original.fetch("rev", nil).nil?
      end

      # Channel tarballs track a channel (e.g. nixos-26.05) rather than a git ref. Non-channel
      # tarballs aren't updatable, so they're skipped.
      sig do
        params(
          input_name: String,
          locked: T::Hash[String, T.untyped],
          original: T::Hash[String, T.untyped],
          rev: String
        ).returns(T.nilable(Dependabot::Dependency))
      end
      def build_tarball_dependency(input_name, locked, original, rev)
        url, channel = channel_tarball_source(locked, original)
        return unless url && channel

        Dependency.new(
          name: input_name,
          version: rev,
          package_manager: "nix",
          requirements: [{
            requirement: nil,
            file: "flake.lock",
            source: { type: "tarball", url: url, branch: nil, ref: channel },
            groups: []
          }]
        )
      end

      # The URL and channel of a tarball input, or nil when it isn't a NixOS channel.
      sig do
        params(
          locked: T::Hash[String, T.untyped],
          original: T::Hash[String, T.untyped]
        ).returns(T.nilable([String, String]))
      end
      def channel_tarball_source(locked, original)
        return indirect_channel_source(locked, original) if original["type"] == "indirect"

        url = original.fetch("url", nil)
        channel = Channel.channel_name_from_url(url)
        [url, channel] if url && channel
      end

      # An indirect input such as `nixpkgs/nixos-unstable` has no URL in the lock: `original` keeps the registry id
      # and ref, and `locked` is the release tarball the registry resolved it to. The channel is the ref, so it is only
      # trusted when the lock really is a NixOS release tarball. The channel's canonical URL stands in for the URL the
      # flake doesn't have, with the locked tarball's suffix kept.
      sig do
        params(
          locked: T::Hash[String, T.untyped],
          original: T::Hash[String, T.untyped]
        ).returns(T.nilable([String, String]))
      end
      def indirect_channel_source(locked, original)
        ref = original.fetch("ref", nil)
        return unless ref.is_a?(String)

        extension = release_tarball_extension(locked.fetch("url", nil))
        return unless extension

        # Round-tripping through the channel URL rejects refs that aren't channel names, such as pull/1489/head.
        url = Channel.url_for(ref, extension: extension)
        channel = Channel.channel_name_from_url(url)
        [url, channel] if channel
      end

      # The compression suffix of a NixOS release tarball URL, or nil for any other URL.
      sig { params(url: T.untyped).returns(T.nilable(String)) }
      def release_tarball_extension(url)
        return unless url.is_a?(String)

        uri = URI.parse(url)
        return unless RELEASE_TARBALL_HOSTS.include?(uri.host)

        RELEASE_TARBALL_PATH.match(uri.path.to_s)&.[](:extension)
      rescue URI::InvalidURIError
        nil
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
          "https://#{host}/#{locked['owner']}/#{locked['repo']}"
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
