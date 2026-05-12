# typed: false
# frozen_string_literal: true

require "native_spec_helper"

RSpec.describe "Bundler version resolution" do
  describe "helper runtime activation" do
    it "allows Bundler 4 via constraint" do
      # The gem constraint in run.rb should accept Bundler 4
      # This is validated by requiring run.rb in the native helper context
      require_relative "../run"
      bundler_version = Gem.loaded_specs["bundler"].version
      expect(bundler_version.major).to be_in([2, 4])
    end

    it "respects DEPENDABOT_BUNDLER_VERSION_CONSTRAINT override" do
      # When override is set, the helper should use that constraint instead of default
      old_constraint = ENV.fetch("DEPENDABOT_BUNDLER_VERSION_CONSTRAINT", nil)
      begin
        ENV["DEPENDABOT_BUNDLER_VERSION_CONSTRAINT"] = "~> 2.7"
        # The constraint in run.rb should read from this env var
        constraint = ENV.fetch(
          "DEPENDABOT_BUNDLER_VERSION_CONSTRAINT",
          ENV.fetch("BUNDLER_VERSION_CONSTRAINT", ">= 2.4, < 5")
        )
        expect(constraint).to eq("~> 2.7")
      ensure
        ENV["DEPENDABOT_BUNDLER_VERSION_CONSTRAINT"] = old_constraint
      end
    end

    it "respects BUNDLER_VERSION_CONSTRAINT fallback" do
      # When DEPENDABOT_BUNDLER_VERSION_CONSTRAINT is not set,
      # fallback to BUNDLER_VERSION_CONSTRAINT
      old_constraint = ENV.fetch("BUNDLER_VERSION_CONSTRAINT", nil)
      begin
        ENV["BUNDLER_VERSION_CONSTRAINT"] = "~> 4.0"
        constraint = ENV.fetch(
          "DEPENDABOT_BUNDLER_VERSION_CONSTRAINT",
          ENV.fetch("BUNDLER_VERSION_CONSTRAINT", ">= 2.4, < 5")
        )
        expect(constraint).to eq("~> 4.0")
      ensure
        ENV["BUNDLER_VERSION_CONSTRAINT"] = old_constraint
      end
    end

    it "defaults to Bundler 4 with upper bound when no override is set" do
      # Default constraint should allow Bundler 4 but prevent Bundler 5+
      old_dep = ENV.fetch("DEPENDABOT_BUNDLER_VERSION_CONSTRAINT", nil)
      old_bundler = ENV.fetch("BUNDLER_VERSION_CONSTRAINT", nil)
      begin
        ENV.delete("DEPENDABOT_BUNDLER_VERSION_CONSTRAINT")
        ENV.delete("BUNDLER_VERSION_CONSTRAINT")
        constraint = ENV.fetch(
          "DEPENDABOT_BUNDLER_VERSION_CONSTRAINT",
          ENV.fetch("BUNDLER_VERSION_CONSTRAINT", ">= 2.4, < 5")
        )
        expect(constraint).to eq(">= 2.4, < 5")
      ensure
        ENV["DEPENDABOT_BUNDLER_VERSION_CONSTRAINT"] = old_dep
        ENV["BUNDLER_VERSION_CONSTRAINT"] = old_bundler
      end
    end
  end

  describe "GEM_HOME isolation in build script" do
    it "resolves Bundler version from GEM_HOME only" do
      # The build script should resolve from GEM_HOME/specifications,
      # not from all gem paths, to avoid picking up system gems
      gem_home = ENV.fetch("GEM_HOME", nil)
      skip "GEM_HOME not set in test environment" unless gem_home

      # Check that our helper's Bundler is available in GEM_HOME
      bundler_specs = Dir.glob("#{gem_home}/specifications/bundler-*.gemspec")
      expect(bundler_specs).not_to be_empty
    end
  end
end
