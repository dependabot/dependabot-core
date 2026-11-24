# typed: strong
# frozen_string_literal: true

require "uri"
require "dependabot/errors"
require "dependabot/nix/channel"
require "dependabot/nix/lockfile"

module Dependabot
  module Nix
    class Lockfile
      class GitInput < T::ImmutableStruct
        extend T::Sig

        const :revision, String
        const :url, String
        const :ref, T.nilable(String), default: nil

        sig { returns(String) }
        def type
          "git"
        end
      end

      class ChannelInput < T::ImmutableStruct
        extend T::Sig

        const :revision, String
        const :url, String
        const :ref, String

        sig { returns(String) }
        def type
          "tarball"
        end
      end

      DependencyInput = T.type_alias { T.any(GitInput, ChannelInput) }

      class InputParser
        extend T::Sig

        SUPPORTED_TYPES = %w(github gitlab sourcehut git tarball).freeze
        DEFAULT_HOSTS = T.let(
          { "github" => "github.com", "gitlab" => "gitlab.com", "sourcehut" => "git.sr.ht" }.freeze,
          T::Hash[String, String]
        )
        RELEASE_HOSTS = %w(releases.nixos.org channels.nixos.org).freeze
        RELEASE_PATH = %r{/nixexprs\.tar\.(?<extension>xz|gz|bz2|zst)\z}

        sig { params(node: Node, path: String, name: String).void }
        def initialize(node, path:, name:)
          @node = node
          @path = path
          @name = name
        end

        sig { returns(T.nilable(DependencyInput)) }
        def parse
          locked = @node["locked"]
          original = @node["original"]
          return unless locked && original

          locked = object(locked, "locked")
          original = object(original, "original")
          type = locked["type"]
          return unless type.is_a?(String) && SUPPORTED_TYPES.include?(type)
          return unless original["rev"].nil?

          revision = locked["rev"]
          return unless revision

          revision = string(revision, "locked.rev")
          return channel_input(locked, original, revision) if type == "tarball"

          url = git_url(locked, type)
          return unless url

          GitInput.new(revision: revision, url: url, ref: optional_string(original["ref"], "original.ref"))
        end

        private

        sig { params(locked: Node, type: String).returns(T.nilable(String)) }
        def git_url(locked, type)
          return optional_string(locked["url"], "locked.url") if type == "git"

          host = optional_string(locked["host"], "locked.host") || DEFAULT_HOSTS.fetch(type)
          owner = string(locked["owner"], "locked.owner")
          repo = string(locked["repo"], "locked.repo")
          "https://#{host}/#{owner}/#{repo}"
        end

        sig { params(locked: Node, original: Node, revision: String).returns(T.nilable(ChannelInput)) }
        def channel_input(locked, original, revision)
          source = if original["type"] == "indirect"
                     indirect_channel(locked, original)
                   else
                     url = optional_string(original["url"], "original.url")
                     channel = Channel.channel_name_from_url(url)
                     [url, channel] if url && channel
                   end
          return unless source

          url, ref = source
          ChannelInput.new(revision: revision, url: url, ref: ref)
        end

        sig { params(locked: Node, original: Node).returns(T.nilable([String, String])) }
        def indirect_channel(locked, original)
          ref = original["ref"]
          return unless ref.is_a?(String)

          extension = release_extension(locked["url"])
          return unless extension

          url = Channel.url_for(ref, extension: extension)
          channel = Channel.channel_name_from_url(url)
          [url, channel] if channel
        end

        sig { params(value: Object).returns(T.nilable(String)) }
        def release_extension(value)
          return unless value.is_a?(String)

          uri = URI.parse(value)
          RELEASE_PATH.match(uri.path.to_s)&.[](:extension) if RELEASE_HOSTS.include?(uri.host)
        rescue URI::InvalidURIError
          nil
        end

        sig { params(value: Object, field: String).returns(Node) }
        def object(value, field)
          invalid!(field, "an object") unless value.is_a?(Hash)

          T.let(value, Node)
        end

        sig { params(value: Object, field: String).returns(String) }
        def string(value, field)
          return value if value.is_a?(String)

          invalid!(field, "a string")
        end

        sig { params(value: Object, field: String).returns(T.nilable(String)) }
        def optional_string(value, field)
          string(value, field) unless value.nil?
        end

        sig { params(field: String, expected: String).returns(T.noreturn) }
        def invalid!(field, expected)
          raise Dependabot::DependencyFileNotParseable.new(@path, "#{@name}.#{field} must be #{expected}")
        end
      end
      private_constant :InputParser
    end
  end
end
