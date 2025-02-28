# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Package
    class ReleaseCooldownOptions
      extend T::Sig

      sig do
        params(
          default_days: Integer,
          major_days: Integer,
          minor_days: Integer,
          patch_days: Integer,
          include: T::Array[String],
          exclude: T::Array[String]
        ).void
      end
      def initialize(
        default_days: 0, major_days: 0, minor_days: 0, patch_days: 0,
        include: [], exclude: []
      )
        @default_days = T.let(default_days, Integer)
        @major_days = T.let(major_days, Integer)
        @minor_days = T.let(minor_days, Integer)
        @patch_days = T.let(patch_days, Integer)
        @include = T.let(include, T::Array[String])
        @exclude = T.let(exclude, T::Array[String])
      end

      sig { returns(Integer) }
      attr_reader :default_days
      sig { returns(T::Array[String]) }
      attr_reader :include
      sig { returns(T::Array[String]) }
      attr_reader :exclude

      sig { returns(Integer) }
      def major_days
        @major_days.positive? ? @major_days : @default_days
      end

      sig { returns(Integer) }
      def minor_days
        @minor_days.positive? ? @minor_days : @default_days
      end

      sig { returns(Integer) }
      def patch_days
        @patch_days.positive? ? @patch_days : @default_days
      end

      sig { params(dependency_name: String).returns(T::Boolean) }
      def included?(dependency_name)
        @include.empty? || @include.any? { |pattern| File.fnmatch?(pattern, dependency_name) }
      end

      sig { params(dependency_name: String).returns(T::Boolean) }
      def excluded?(dependency_name)
        @exclude.any? { |pattern| File.fnmatch?(pattern, dependency_name) }
      end
    end
  end
end
