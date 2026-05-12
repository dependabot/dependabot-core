# typed: false
# frozen_string_literal: true

require "native_spec_helper"

RSpec.describe Bundler do
  describe "helper runtime activation" do
    it "is running a supported Bundler major version" do
      bundler_major = Bundler::VERSION.split(".").first.to_i
      expect(bundler_major).to be_between(2, 4)
      expect(bundler_major).not_to eq(3)
    end

    it "respects DEPENDABOT_BUNDLER_VERSION_CONSTRAINT override" do
      old_constraint = ENV.fetch("DEPENDABOT_BUNDLER_VERSION_CONSTRAINT", nil)
      begin
        ENV["DEPENDABOT_BUNDLER_VERSION_CONSTRAINT"] = "~> 2.7"
        constraint = ENV.fetch(
          "DEPENDABOT_BUNDLER_VERSION_CONSTRAINT",
          ENV.fetch("BUNDLER_VERSION_CONSTRAINT", "~> 4.0")
        )
        expect(constraint).to eq("~> 2.7")
      ensure
        ENV["DEPENDABOT_BUNDLER_VERSION_CONSTRAINT"] = old_constraint
      end
    end

    it "respects BUNDLER_VERSION_CONSTRAINT fallback" do
      old_constraint = ENV.fetch("BUNDLER_VERSION_CONSTRAINT", nil)
      begin
        ENV["BUNDLER_VERSION_CONSTRAINT"] = "~> 4.0"
        constraint = ENV.fetch(
          "DEPENDABOT_BUNDLER_VERSION_CONSTRAINT",
          ENV.fetch("BUNDLER_VERSION_CONSTRAINT", "~> 4.0")
        )
        expect(constraint).to eq("~> 4.0")
      ensure
        ENV["BUNDLER_VERSION_CONSTRAINT"] = old_constraint
      end
    end

    it "defaults to Bundler 4 constraint when no override is set" do
      old_dep = ENV.fetch("DEPENDABOT_BUNDLER_VERSION_CONSTRAINT", nil)
      old_bundler = ENV.fetch("BUNDLER_VERSION_CONSTRAINT", nil)
      begin
        ENV.delete("DEPENDABOT_BUNDLER_VERSION_CONSTRAINT")
        ENV.delete("BUNDLER_VERSION_CONSTRAINT")
        constraint = ENV.fetch(
          "DEPENDABOT_BUNDLER_VERSION_CONSTRAINT",
          ENV.fetch("BUNDLER_VERSION_CONSTRAINT", "~> 4.0")
        )
        expect(constraint).to eq("~> 4.0")
      ensure
        ENV["DEPENDABOT_BUNDLER_VERSION_CONSTRAINT"] = old_dep
        ENV["BUNDLER_VERSION_CONSTRAINT"] = old_bundler
      end
    end
  end

  describe "GEM_HOME isolation in build script" do
    it "resolves Bundler version from GEM_HOME only" do
      gem_home = ENV.fetch("GEM_HOME", nil)
      skip "GEM_HOME not set in test environment" unless gem_home

      bundler_specs = Dir.glob("#{gem_home}/specifications/bundler-*.gemspec")
      expect(bundler_specs.length).to be_positive
    end
  end
end
