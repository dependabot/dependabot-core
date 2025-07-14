# typed: strong
# frozen_string_literal: true

require "dependabot/requirement"
require "dependabot/utils"

require "dependabot/rust_toolchain"
require "dependabot/rust_toolchain/version"
require "dependabot/rust_toolchain/channel_parser"
require "dependabot/rust_toolchain/channel_type"

module Dependabot
  module RustToolchain
    class Requirement < Dependabot::Requirement
      # For consistency with other languages, we define a requirements array.
      # rust-toolchain always contains a single element.
      sig { override.params(requirement_string: T.nilable(String)).returns(T::Array[Dependabot::Requirement]) }
      def self.requirements_array(requirement_string)
        [new(requirement_string)]
      end

      sig do
        params(obj: T.any(String, Gem::Version)).returns(T::Array[T.any(String, Dependabot::RustToolchain::Version)])
      end
      def self.parse(obj)
        return ["=", RustToolchain::Version.new(obj.to_s)] if obj.is_a?(Gem::Version)

        requirement_string = obj.to_s.strip

        # Parse requirement strings with operators (e.g., ">= 1.72.0")
        match = requirement_string.match(/^(>=|>|<=|<|=)\s?(.+)$/)
        if match
          operator = T.must(match[1])
          version_string = T.must(match[2]).strip

          # Special case: handle ">= 0" which is used to represent "all versions"
          return [operator, RustToolchain::Version.new("0.0.0")] if version_string == "0"

          # Validate the version string
          if RustToolchain::Version.correct?(version_string)
            return [operator, RustToolchain::Version.new(version_string)]
          end
        end

        # Handle bare version strings (no operator)
        if requirement_string == "0"
          # Special case: handle bare "0" as "0.0.0"
          return ["=", RustToolchain::Version.new("0.0.0")]
        end

        if RustToolchain::Version.correct?(requirement_string)
          return ["=", RustToolchain::Version.new(requirement_string)]
        end

        # If it's not a valid Rust toolchain format, fall back to default
        msg = "Illformed requirement [#{obj.inspect}]"
        raise BadRequirementError, msg
      end

      # Patches Gem::Requirement to make it accept requirement strings like
      # "~> 4.2.5, >= 4.2.5.1" without first needing to split them.
      sig { params(requirements: T.nilable(String)).void }
      def initialize(*requirements)
        requirements = requirements.flatten.flat_map do |req_string|
          req_string&.split(",")&.map(&:strip)
        end.compact

        super(requirements)
      end

      # rubocop:disable Metrics/AbcSize
      sig { override.params(version: T.any(Gem::Version, String)).returns(T::Boolean) }
      def satisfied_by?(version)
        version = RustToolchain::Version.new(version.to_s) unless version.is_a?(RustToolchain::Version)

        T.cast(requirements, T::Array[T::Array[T.untyped]]).all? do |req|
          op = T.cast(req[0], String)
          rv = T.cast(req[1], RustToolchain::Version)

          case op
          when "="
            satisfy_exact_requirement?(version, rv)
          when ">="
            satisfy_greater_than_or_equal_requirement?(version, rv)
          when ">"
            satisfy_greater_than_requirement?(version, rv)
          when "<="
            satisfy_less_than_or_equal_requirement?(version, rv)
          when "<"
            satisfy_less_than_requirement?(version, rv)
          else
            # Fall back to default behavior for other operators
            ops_method = T.let(OPS[op], T.nilable(T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean)))
            ops_method ||= T.cast(OPS["="], T.proc.params(arg0: T.untyped, arg1: T.untyped).returns(T::Boolean))
            ops_method.call(version, rv)
          end
        end
      end
      # rubocop:enable Metrics/AbcSize

      private

      # Check if version satisfies exact requirement
      sig { params(version: RustToolchain::Version, requirement_version: RustToolchain::Version).returns(T::Boolean) }
      def satisfy_exact_requirement?(version, requirement_version)
        return version == requirement_version if version.channel.nil? || requirement_version.channel.nil?

        v_channel = T.must(version.channel)
        r_channel = T.must(requirement_version.channel)

        # Channels must be of the same type and equal
        v_channel.channel_type == r_channel.channel_type && v_channel == r_channel
      end

      # Check if version satisfies >= requirement
      sig { params(version: RustToolchain::Version, requirement_version: RustToolchain::Version).returns(T::Boolean) }
      def satisfy_greater_than_or_equal_requirement?(version, requirement_version)
        return version >= requirement_version if version.channel.nil? || requirement_version.channel.nil?

        v_channel = T.must(version.channel)
        r_channel = T.must(requirement_version.channel)

        # Can only compare channels of the same type
        return false unless v_channel.channel_type == r_channel.channel_type

        case v_channel.channel_type
        when ChannelType::Version
          # Compare semantic versions
          v_channel >= r_channel
        when ChannelType::DatedStability
          # Must be same stability level to compare dates
          return false unless v_channel.stability == r_channel.stability

          v_channel >= r_channel
        when ChannelType::Stability
          # Stability channels can be ordered: stable > beta > nightly
          stability_order(v_channel.stability) >= stability_order(r_channel.stability)
        else
          false
        end
      end

      # Check if version satisfies > requirement
      sig { params(version: RustToolchain::Version, requirement_version: RustToolchain::Version).returns(T::Boolean) }
      def satisfy_greater_than_requirement?(version, requirement_version)
        return version > requirement_version if version.channel.nil? || requirement_version.channel.nil?

        v_channel = T.must(version.channel)
        r_channel = T.must(requirement_version.channel)

        # Can only compare channels of the same type
        return false unless v_channel.channel_type == r_channel.channel_type

        case v_channel.channel_type
        when ChannelType::Version
          v_channel > r_channel
        when ChannelType::DatedStability
          return false unless v_channel.stability == r_channel.stability

          v_channel > r_channel
        when ChannelType::Stability
          stability_order(v_channel.stability) > stability_order(r_channel.stability)
        else
          false
        end
      end

      # Check if version satisfies <= requirement
      sig { params(version: RustToolchain::Version, requirement_version: RustToolchain::Version).returns(T::Boolean) }
      def satisfy_less_than_or_equal_requirement?(version, requirement_version)
        return version <= requirement_version if version.channel.nil? || requirement_version.channel.nil?

        v_channel = T.must(version.channel)
        r_channel = T.must(requirement_version.channel)

        # Can only compare channels of the same type
        return false unless v_channel.channel_type == r_channel.channel_type

        case v_channel.channel_type
        when ChannelType::Version
          v_channel <= r_channel
        when ChannelType::DatedStability
          return false unless v_channel.stability == r_channel.stability

          v_channel <= r_channel
        when ChannelType::Stability
          stability_order(v_channel.stability) <= stability_order(r_channel.stability)
        else
          false
        end
      end

      # Check if version satisfies < requirement
      sig { params(version: RustToolchain::Version, requirement_version: RustToolchain::Version).returns(T::Boolean) }
      def satisfy_less_than_requirement?(version, requirement_version)
        return version < requirement_version if version.channel.nil? || requirement_version.channel.nil?

        v_channel = T.must(version.channel)
        r_channel = T.must(requirement_version.channel)

        # Can only compare channels of the same type
        return false unless v_channel.channel_type == r_channel.channel_type

        case v_channel.channel_type
        when ChannelType::Version
          v_channel < r_channel
        when ChannelType::DatedStability
          return false unless v_channel.stability == r_channel.stability

          v_channel < r_channel
        when ChannelType::Stability
          stability_order(v_channel.stability) < stability_order(r_channel.stability)
        else
          false
        end
      end

      # Define stability ordering for comparison
      # stable (3) > beta (2) > nightly (1)
      sig { params(stability: T.nilable(String)).returns(Integer) }
      def stability_order(stability)
        case stability
        when STABLE_CHANNEL then 3
        when BETA_CHANNEL then 2
        when NIGHTLY_CHANNEL then 1
        else 0
        end
      end
    end
  end
end

Dependabot::Utils.register_requirement_class("rust_toolchain", Dependabot::RustToolchain::Requirement)
