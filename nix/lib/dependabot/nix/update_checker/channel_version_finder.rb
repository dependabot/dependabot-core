# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/nix/update_checker"
require "dependabot/nix/channel"
require "dependabot/nix/ignore_filter"
require "dependabot/registry_client"

module Dependabot
  module Nix
    class UpdateChecker
      # Finds the latest NixOS channel and its revision: channels come from the
      # channels.nixos.org S3 listing, revisions from each channel's git-revision marker.
      class ChannelVersionFinder
        extend T::Sig

        CHANNELS_BASE_URL = "https://channels.nixos.org"
        CHANNEL_KEY_PATTERN = %r{<Key>([^<]+)</Key>}
        SHA_PATTERN = /\A[0-9a-f]{40}\z/

        sig do
          params(
            current_channel: String,
            credentials: T::Array[Dependabot::Credential],
            ignored_versions: T::Array[String],
            extension: String
          ).void
        end
        def initialize(current_channel:, credentials:, ignored_versions: [], extension: Channel::DEFAULT_EXTENSION)
          @current_channel = T.let(Channel.new(current_channel), Channel)
          @credentials = credentials
          @ignored_versions = ignored_versions
          @extension = extension
          @available_channels = T.let(nil, T.nilable(T::Array[String]))
          @ignore_filter = T.let(nil, T.nilable(IgnoreFilter))
        end

        # Newest same-family channel with its revision, or nil (rolling channel,
        # already latest, or revision unresolvable).
        sig { returns(T.nilable(T::Hash[Symbol, String])) }
        def latest_channel
          return unless current_channel.versioned?

          candidate = newest_candidate
          return unless candidate

          rev = resolve_revision(candidate.name)
          return unless rev

          { channel: candidate.name, url: Channel.url_for(candidate.name, extension: extension), commit_sha: rev }
        end

        # Current channel's revision (refresh path).
        sig { returns(T.nilable(String)) }
        def current_channel_revision
          resolve_revision(current_channel.name)
        end

        private

        sig { returns(Channel) }
        attr_reader :current_channel

        sig { returns(T::Array[Dependabot::Credential]) }
        attr_reader :credentials

        sig { returns(T::Array[String]) }
        attr_reader :ignored_versions

        sig { returns(String) }
        attr_reader :extension

        sig { returns(T.nilable(Channel)) }
        def newest_candidate
          candidates = available_channels
                       .map { |name| Channel.new(name) }
                       .select { |channel| channel.same_family?(current_channel) }
                       .select { |channel| channel.newer_than?(current_channel) }
                       .reject { |channel| ignore_filter.ignored?(channel.version_string) }

          candidates.max_by { |channel| T.must(channel.version) }
        end

        sig { returns(T::Array[String]) }
        def available_channels
          @available_channels ||= fetch_available_channels
        end

        sig { returns(T::Array[String]) }
        def fetch_available_channels
          prefix = current_channel.prefix
          return [] unless prefix

          url = "#{CHANNELS_BASE_URL}/?delimiter=/&list-type=2&prefix=#{prefix}"
          response = Dependabot::RegistryClient.get(url: url)
          return [] unless response.status == 200

          response.body.to_s.scan(CHANNEL_KEY_PATTERN).flatten
        rescue StandardError => e
          Dependabot.logger.info("Failed to list NixOS channels: #{e.class}: #{e.message}")
          []
        end

        sig { params(channel: String).returns(T.nilable(String)) }
        def resolve_revision(channel)
          url = "#{CHANNELS_BASE_URL}/#{channel}/git-revision"
          response = Dependabot::RegistryClient.get(url: url)
          return unless response.status == 200

          rev = response.body.to_s.strip
          rev if rev.match?(SHA_PATTERN)
        rescue StandardError => e
          Dependabot.logger.info("Failed to resolve revision for #{channel}: #{e.class}: #{e.message}")
          nil
        end

        sig { returns(IgnoreFilter) }
        def ignore_filter
          @ignore_filter ||= IgnoreFilter.new(ignored_versions)
        end
      end
    end
  end
end
