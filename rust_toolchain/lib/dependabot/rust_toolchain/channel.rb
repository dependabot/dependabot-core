# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/rust_toolchain/channel_type"

module Dependabot
  module RustToolchain
    class Channel
      extend T::Sig

      include Comparable

      sig { returns(T.nilable(String)) }
      attr_reader :stability

      sig { returns(T.nilable(String)) }
      attr_reader :date

      sig { returns(T.nilable(String)) }
      attr_accessor :version

      sig { params(stability: T.nilable(String), date: T.nilable(String), version: T.nilable(String)).void }
      def initialize(stability: nil, date: nil, version: nil)
        @stability = stability
        @date = date
        @version = version
      end

      # Factory method to create a Channel from parser output
      sig { params(parsed_data: T::Hash[Symbol, T.nilable(String)]).returns(Channel) }
      def self.from_parsed_data(parsed_data)
        new(
          stability: parsed_data[:stability],
          date: parsed_data[:date],
          version: parsed_data[:version]
        )
      end

      # Returns the channel type for comparison purposes
      sig { returns(Dependabot::RustToolchain::ChannelType) }
      def channel_type
        case [!!version, !!(stability && date), !!stability]
        in [true, _, _] then ChannelType::Version
        in [false, true, _] then ChannelType::DatedStability
        in [false, false, true] then ChannelType::Stability
        else ChannelType::Unknown
        end
      end

      # Comparable implementation - only compare channels of the same type
      sig { params(other: Object).returns(T.nilable(Integer)) }
      def <=>(other)
        return nil unless other.is_a?(Channel)
        return nil unless channel_type == other.channel_type

        case channel_type
        in ChannelType::Version
          compare_versions(T.must(version), T.must(other.version))
        in ChannelType::DatedStability
          # Channels must be of the same type to compare dates
          # i.e. cannot compare "nightly-2023-10-01" with "beta-2023-10-01"
          return nil unless stability == other.stability

          compare_dates(T.must(date), T.must(other.date))
        end
      end

      sig { params(other: Object).returns(T::Boolean) }
      def ==(other)
        return false unless other.is_a?(Channel)

        stability == other.stability && date == other.date && version == other.version
      end

      sig { returns(String) }
      def to_s
        case [version, stability, date]
        in [String => v, _, _] then v
        in [nil, String => c, String => d] then "#{c}-#{d}"
        in [nil, String => c, _] then c
        else "unknown"
        end
      end

      sig { returns(String) }
      def inspect
        "#<#{self.class.name} channel=#{stability.inspect} date=#{date.inspect} version=#{version.inspect}>"
      end

      private

      # Compare semantic versions (e.g., "1.72.0" vs "1.73.1")
      sig { params(version1: String, version2: String).returns(Integer) }
      def compare_versions(version1, version2)
        v1_parts = version1.split(".").map(&:to_i)
        v2_parts = version2.split(".").map(&:to_i)

        # Pad shorter version parts with zeros to ensure equal length
        max_length = [v1_parts.size, v2_parts.size].max
        v1_parts.fill(0, v1_parts.size...max_length) if v1_parts.size < max_length
        v2_parts.fill(0, v2_parts.size...max_length) if v2_parts.size < max_length

        v1_parts <=> v2_parts
      end

      # Compare dates in YYYY-MM-DD format
      sig { params(date1: String, date2: String).returns(Integer) }
      def compare_dates(date1, date2)
        T.must(date1 <=> date2)
      end
    end
  end
end
