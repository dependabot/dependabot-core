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

      sig do
        params(
          current_semver: T.nilable([Integer, Integer, Integer]),
          new_semver: T.nilable([Integer, Integer, Integer])
        ).returns(Integer)
      end
      def cooldown_days_for(current_semver, new_semver)
        return @default_days if current_semver.nil? || new_semver.nil?

        current_major, current_minor, current_patch = current_semver
        new_major, new_minor, new_patch = new_semver

        return @semver_major_days if T.must(new_major) > T.must(current_major)

        if T.must(new_major) == T.must(current_major)
          return @semver_minor_days if T.must(new_minor) > T.must(current_minor)
          return @semver_patch_days if T.must(new_minor) == T.must(current_minor) &&
                                       T.must(new_patch) > T.must(current_patch)
        end

        @default_days
      end

      private

      sig { params(dependency_name: String).returns(T::Boolean) }
      def excluded?(dependency_name)
        @exclude.any? { |pattern| File.fnmatch?(pattern, dependency_name) }
      end
    end
  end
end
