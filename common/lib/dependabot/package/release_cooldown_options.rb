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
          semver_major_days: T.nilable(Integer),
          semver_minor_days: T.nilable(Integer),
          semver_patch_days: T.nilable(Integer),
          include: T.nilable(T::Array[String]),
          exclude: T.nilable(T::Array[String])
        ).void
      end
      def initialize(
        default_days: 0,
        semver_major_days: 0,
        semver_minor_days: 0,
        semver_patch_days: 0,
        include: [],
        exclude: []
      )
        default_days ||= 0
        semver_major_days ||= 0
        semver_minor_days ||= 0
        semver_patch_days ||= 0
        include ||= []
        exclude ||= []

        @default_days = T.let(default_days, Integer)
        @semver_major_days = T.let(semver_major_days.positive? ? semver_major_days : default_days, Integer)
        @semver_minor_days = T.let(semver_minor_days.positive? ? semver_minor_days : default_days, Integer)
        @semver_patch_days = T.let(semver_patch_days.positive? ? semver_patch_days : default_days, Integer)
        @include = T.let(include.to_set, T::Set[String])
        @exclude = T.let(exclude.to_set, T::Set[String])
      end

      sig { returns(Integer) }
      attr_reader :default_days, :semver_major_days, :semver_minor_days, :semver_patch_days

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
