# typed: false
# frozen_string_literal: true

require "native_spec_helper"
require_relative "../lib/bundler_version_constraint"

RSpec.describe BundlerVersionConstraint do
  describe "helper runtime activation" do
    it "is running a supported Bundler major version" do
      # Bundler 3 was intentionally skipped upstream (Bundler jumped from 2.7
      # straight to 4.0 to align with RubyGems) so the supported window is
      # 2.x or 4.x.
      bundler_major = Bundler::VERSION.split(".").first.to_i
      expect(bundler_major).to be_between(2, 4)
    end
  end

  describe ".resolve" do
    it "returns the DEPENDABOT_BUNDLER_VERSION_CONSTRAINT override when set" do
      env = { "DEPENDABOT_BUNDLER_VERSION_CONSTRAINT" => "~> 2.7" }
      expect(described_class.resolve(env: env)).to eq("~> 2.7")
    end

    it "prefers DEPENDABOT_BUNDLER_VERSION_CONSTRAINT over BUNDLER_VERSION_CONSTRAINT" do
      env = {
        "DEPENDABOT_BUNDLER_VERSION_CONSTRAINT" => "~> 2.7",
        "BUNDLER_VERSION_CONSTRAINT" => "~> 4.0"
      }
      expect(described_class.resolve(env: env)).to eq("~> 2.7")
    end

    it "falls back to BUNDLER_VERSION_CONSTRAINT when only that is set" do
      env = { "BUNDLER_VERSION_CONSTRAINT" => "~> 4.0" }
      expect(described_class.resolve(env: env)).to eq("~> 4.0")
    end

    it "uses the default activation constraint when no env var is set" do
      expect(described_class.resolve(env: {})).to eq(">= 2.4, < 5")
    end

    it "honours an explicit default override" do
      expect(described_class.resolve(env: {}, default: "~> 4.0")).to eq("~> 4.0")
    end
  end

  describe ".activation_clauses" do
    it "splits comma-separated requirement strings into trimmed clauses" do
      expect(described_class.activation_clauses(">= 2.4, < 5")).to eq([">= 2.4", "< 5"])
    end

    it "returns a single clause for a single requirement" do
      expect(described_class.activation_clauses("~> 4.0")).to eq(["~> 4.0"])
    end
  end

  describe "build script GEM_HOME isolation" do
    it "resolves Bundler version from GEM_HOME only" do
      gem_home = ENV.fetch("GEM_HOME", nil)
      skip "GEM_HOME not set in test environment" unless gem_home

      bundler_specs = Dir.glob("#{gem_home}/specifications/bundler-*.gemspec")
      expect(bundler_specs.length).to be_positive
    end
  end
end
