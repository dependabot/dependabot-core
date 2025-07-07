# typed: strict
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

require "dependabot/rust_toolchain/channel_parser"
require "dependabot/rust_toolchain/channel_type"

module Dependabot
  module RustToolchain
    class Version < Dependabot::Version
      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        raise BadRequirementError, "Malformed channel string - string is nil" if version.nil?

        @version_string = T.let(version.to_s.strip, String)
        @channel = T.let(
          Dependabot::RustToolchain::ChannelParser.new(@version_string).parse,
          T.nilable(Dependabot::RustToolchain::Channel)
        )

        super(@version_string)
      end

      sig { override.params(version: VersionParameter).returns(Dependabot::RustToolchain::Version) }
      def self.new(version)
        T.cast(super, Dependabot::RustToolchain::Version)
      end

      sig { override.params(version: VersionParameter).returns(T::Boolean) }
      def self.correct?(version)
        return false if version.to_s.empty?

        !Dependabot::RustToolchain::ChannelParser.new(version.to_s).parse.nil?
      rescue ArgumentError
        Dependabot.logger.info("Malformed version string #{version}")
        false
      end

      sig { override.returns(String) }
      def to_s
        return "" if @channel.nil?

        case @channel.channel_type
        in ChannelType::Version
          T.must(@channel.version)
        in ChannelType::DatedStability
          "#{@channel.stability}-#{@channel.date}"
        in ChannelType::Stability
          T.must(@channel.stability)
        else
          ""
        end
      end

      sig { returns(T.nilable(Dependabot::RustToolchain::Channel)) }
      attr_reader :channel
    end
  end
end

Dependabot::Utils
  .register_version_class("rust_toolchain", Dependabot::RustToolchain::Version)
