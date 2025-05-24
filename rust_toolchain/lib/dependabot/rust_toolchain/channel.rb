# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module RustToolchain
    class Channel
      extend T::Sig

      include Comparable

      sig { returns(T.nilable(String)) }
      attr_reader :channel

      sig { returns(T.nilable(String)) }
      attr_reader :date

      sig { returns(T.nilable(String)) }
      attr_accessor :version

      # Stability order: stable > beta > nightly
      CHANNEL_ORDER = T.let({ "stable" => 3, "beta" => 2, "nightly" => 1 }.freeze, T::Hash[String, Integer])

      sig { params(channel: T.nilable(String), date: T.nilable(String), version: T.nilable(String)).void }
      def initialize(channel: nil, date: nil, version: nil)
        @channel = channel
        @date = date
        @version = version
      end

      # Factory method to create a Channel from parser output
      sig { params(parsed_data: T::Hash[Symbol, T.nilable(String)]).returns(Channel) }
      def self.from_parsed_data(parsed_data)
        new(
          channel: parsed_data[:channel],
          date: parsed_data[:date],
          version: parsed_data[:version]
        )
      end

      # Returns the channel type for comparison purposes
      sig { returns(Symbol) }
      def channel_type
        case [!!version, !!(channel && date), !!channel]
        in [true, _, _] then :version
        in [false, true, _] then :dated_channel
        in [false, false, true] then :channel
        else :unknown
        end
      end

      # Comparable implementation - only compare channels of the same type
      sig { params(other: Object).returns(T.nilable(Integer)) }
      def <=>(other)
        return nil unless other.is_a?(Channel)
        return nil unless channel_type == other.channel_type

        case channel_type
        in :version
          compare_versions(T.must(version), T.must(other.version))
        in :dated_channel
          # First compare by channel, then by date if same channel
          channel_comparison = compare_channels(T.must(channel), T.must(other.channel))
          return channel_comparison unless channel_comparison.zero?

          compare_dates(T.must(date), T.must(other.date))
        in :channel
          compare_channels(T.must(channel), T.must(other.channel))
        end
      end

      sig { params(other: Object).returns(T::Boolean) }
      def ==(other)
        return false unless other.is_a?(Channel)

        channel == other.channel && date == other.date && version == other.version
      end

      sig { returns(String) }
      def to_s
        case [version, channel, date]
        in [String => v, _, _] then v
        in [nil, String => c, String => d] then "#{c}-#{d}"
        in [nil, String => c, _] then c
        else "unknown"
        end
      end

      sig { returns(String) }
      def inspect
        "#<#{self.class.name} channel=#{channel.inspect} date=#{date.inspect} version=#{version.inspect}>"
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

      # Compare channel names with stability ordering
      sig { params(channel1: String, channel2: String).returns(Integer) }
      def compare_channels(channel1, channel2)
        order1 = CHANNEL_ORDER.fetch(channel1, 0)
        order2 = CHANNEL_ORDER.fetch(channel2, 0)

        order1 <=> order2
      end

      # Compare dates in YYYY-MM-DD format
      sig { params(date1: String, date2: String).returns(Integer) }
      def compare_dates(date1, date2)
        T.must(date1 <=> date2)
      end
    end
  end
end
