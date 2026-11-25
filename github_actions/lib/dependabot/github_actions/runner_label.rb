# typed: strong
# frozen_string_literal: true

require "sorbet-runtime"

require "dependabot/dependency"
require "dependabot/github_actions/constants"

module Dependabot
  module GithubActions
    # A hosted runner label like `ubuntu-24.04` or `macos-15-xlarge`. The family
    # (`ubuntu`, `macos-xlarge`) becomes the dependency name and the image version
    # becomes its version.
    class RunnerLabel
      extend T::Sig

      RUNNER_IMAGES_URL = "https://github.com/actions/runner-images#available-images"

      # GA images per family, oldest first, copied by hand from
      # https://github.com/actions/runner-images#available-images. Add a version when
      # it leaves beta, and keep deprecated ones until GitHub drops them. Any other
      # version is ignored, which keeps self-hosted look-alikes like `ubuntu-24` out of it.
      AVAILABLE_VERSIONS = T.let(
        {
          "ubuntu" => %w(22.04 24.04 26.04),
          "ubuntu-arm" => %w(22.04 24.04 26.04),
          "windows" => %w(2022 2025),
          "macos" => %w(14 15 26),
          "macos-xlarge" => %w(14 15 26),
          "macos-large" => %w(14 15 26),
          "macos-intel" => %w(15 26)
        }.freeze,
        T::Hash[String, T::Array[String]]
      )

      LABEL_PATTERN = /\A(?<os>ubuntu|windows|macos)-(?<version>\d+(?:\.\d+)?)(?<suffix>-[a-z]+)?\z/

      sig { params(label: String).returns(T.nilable(RunnerLabel)) }
      def self.parse(label)
        match = label.match(LABEL_PATTERN)
        return unless match

        runner = new(
          os: T.must(match[:os]),
          version: T.must(match[:version]),
          suffix: match[:suffix].to_s
        )
        runner if AVAILABLE_VERSIONS.fetch(runner.family, []).include?(runner.version)
      end

      sig { params(dependency: Dependabot::Dependency).returns(T::Boolean) }
      def self.dependency?(dependency)
        dependency.requirements.any? { |req| req.source_string("type") == RUNNER_SOURCE_TYPE }
      end

      sig { params(os: String, version: String, suffix: String).void }
      def initialize(os:, version:, suffix:)
        @os = os
        @version = version
        @suffix = suffix
      end

      sig { returns(String) }
      attr_reader :version

      sig { returns(String) }
      def family = "#{@os}#{@suffix}"

      sig { params(version: String).returns(String) }
      def with_version(version) = "#{@os}-#{version}#{@suffix}"
    end
  end
end
