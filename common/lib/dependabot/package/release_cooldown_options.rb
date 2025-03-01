# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module Package
    class ReleaseCooldownOptions
      extend T::Sig

      sig do
        params(
          default_days: T.nilable(Integer),
          major_days: T.nilable(Integer),
          minor_days: T.nilable(Integer),
          patch_days: T.nilable(Integer),
          include: T.nilable(T::Array[String]),
          exclude: T.nilable(T::Array[String])
        ).void
      end
      def initialize(
        default_days: 0, major_days: 0, minor_days: 0, patch_days: 0,
        include: [], exclude: []
      )
        default_days ||= 0
        major_days ||= 0
        minor_days ||= 0
        patch_days ||= 0
        include ||= []
        exclude ||= []

        @default_days = T.let(default_days, Integer)
        @major_days = T.let(major_days.positive? ? major_days : default_days, Integer)
        @minor_days = T.let(minor_days.positive? ? minor_days : default_days, Integer)
        @patch_days = T.let(patch_days.positive? ? patch_days : default_days, Integer)
        @include = T.let(include.to_set, T::Set[String])
        @exclude = T.let(exclude.to_set, T::Set[String])
      end

      sig { returns(Integer) }
      attr_reader :default_days, :major_days, :minor_days, :patch_days

      sig { returns(T::Set[String]) }
      attr_reader :include, :exclude

      sig { params(dependency_name: String).returns(T::Boolean) }
      def included?(dependency_name)
        return false if dependency_name.empty? || excluded?(dependency_name)

        @include.empty? || @include.any? { |pattern| File.fnmatch?(pattern, dependency_name) }
      end

      private

      sig { params(dependency_name: String).returns(T::Boolean) }
      def excluded?(dependency_name)
        @exclude.any? { |pattern| File.fnmatch?(pattern, dependency_name) }
      end
    end
  end
end
