# typed: strong
# frozen_string_literal: true

require "dependabot/version"
require "dependabot/utils"

module Dependabot
  module Bazel
    class Version < Dependabot::Version
      extend T::Sig

      sig { override.params(version: VersionParameter).void }
      def initialize(version)
        @original_version = T.let(version.to_s, String)
        @bcr_suffix = T.let(parse_bcr_suffix(@original_version), T.nilable(Integer))

        base_version = remove_bcr_suffix(@original_version)
        super(base_version)

        @original_version = version.to_s
      end

      sig { override.returns(String) }
      def to_s
        @original_version
      end

      sig { returns(T.nilable(Integer)) }
      attr_reader :bcr_suffix

      sig { override.params(other: T.untyped).returns(T.nilable(Integer)) }
      def <=>(other)
        other_bazel = convert_to_bazel_version(other)
        return nil unless other_bazel

        base_comparison = super(other_bazel)
        return base_comparison unless base_comparison&.zero?

        compare_bcr_suffixes(@bcr_suffix, other_bazel.bcr_suffix)
      end

      private

      sig { params(version_string: String).returns(T.nilable(Integer)) }
      def parse_bcr_suffix(version_string)
        match = version_string.match(/\.bcr\.(\d+)$/)
        match ? T.must(match[1]).to_i : nil
      end

      sig { params(version_string: String).returns(String) }
      def remove_bcr_suffix(version_string)
        version_string.sub(/\.bcr\.\d+$/, "")
      end

      sig { params(other: T.untyped).returns(T.nilable(Dependabot::Bazel::Version)) }
      def convert_to_bazel_version(other)
        case other
        when Dependabot::Bazel::Version
          other
        when Gem::Version
          T.cast(Dependabot::Bazel::Version.new(other.to_s), Dependabot::Bazel::Version)
        when String
          T.cast(Dependabot::Bazel::Version.new(other), Dependabot::Bazel::Version)
        when Dependabot::Version
          T.cast(Dependabot::Bazel::Version.new(other.to_s), Dependabot::Bazel::Version)
        end
      end

      sig { params(ours: T.nilable(Integer), theirs: T.nilable(Integer)).returns(Integer) }
      def compare_bcr_suffixes(ours, theirs)
        return ours <=> theirs if ours && theirs

        return 1 if ours
        return -1 if theirs

        0
      end
    end
  end
end

Dependabot::Utils
  .register_version_class("bazel", Dependabot::Bazel::Version)
