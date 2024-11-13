# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bundler/helpers"

RSpec.describe Dependabot::Bundler::Helpers do
  let(:no_lockfile) { nil }
  let(:no_gemfile) { nil }
  let(:no_ruby_version_file) { nil }

  let(:gemfile_with_ruby_version) do
    Dependabot::DependencyFile.new(name: "Gemfile", content: <<~GEMFILE)
      source 'https://rubygems.org'
      ruby '3.0.0'
      gem 'rails'
    GEMFILE
  end

  let(:lockfile_with_ruby_version) do
    Dependabot::DependencyFile.new(name: "Gemfile.lock", content: <<~LOCKFILE)
      RUBY VERSION
         ruby 2.7.2
    LOCKFILE
  end

  let(:lockfile_bundled_with_v1) do
    Dependabot::DependencyFile.new(name: "Gemfile.lock", content: <<~LOCKFILE)
      BUNDLED WITH
        1.17.3
    LOCKFILE
  end

  let(:lockfile_bundled_with_v2) do
    Dependabot::DependencyFile.new(name: "Gemfile.lock", content: <<~LOCKFILE)
      BUNDLED WITH
        2.2.11
    LOCKFILE
  end

  let(:lockfile_bundled_with_future_version) do
    Dependabot::DependencyFile.new(name: "Gemfile.lock", content: <<~LOCKFILE)
      BUNDLED WITH
        3.9.99
    LOCKFILE
  end

  let(:lockfile_bundled_with_missing) do
    Dependabot::DependencyFile.new(name: "Gemfile.lock", content: <<~LOCKFILE)
      Mock Gemfile.lock Content Goes Here
    LOCKFILE
  end

  let(:ruby_version_file) do
    Dependabot::DependencyFile.new(name: ".ruby-version", content: "ruby-2.7.1")
  end

  describe "#bundler_version" do
    def described_method(lockfile)
      described_class.bundler_version(lockfile)
    end

    it "is 2 if there is no lockfile" do
      expect(described_method(no_lockfile)).to eq("2")
    end

    it "is 2 if there is no bundled with string" do
      expect(described_method(lockfile_bundled_with_missing)).to eq("2")
    end

    it "is 1 if it was bundled with a v1.x version" do
      expect(described_method(lockfile_bundled_with_v1)).to eq("1")
    end

    it "is 2 if it was bundled with a v2.x version" do
      expect(described_method(lockfile_bundled_with_v2)).to eq("2")
    end

    it "is 2 if it was bundled with a future version" do
      expect(described_method(lockfile_bundled_with_future_version)).to eq("2")
    end
  end

  describe "#detected_bundler_version" do
    def described_method(lockfile)
      described_class.detected_bundler_version(lockfile)
    end

    it "is unknown if there is no lockfile" do
      expect(described_method(no_lockfile)).to eq("unknown")
    end

    it "is unspecified if there is no bundled with string" do
      expect(described_method(lockfile_bundled_with_missing)).to eq("unspecified")
    end

    it "is 1 if it was bundled with a v1.x version" do
      expect(described_method(lockfile_bundled_with_v1)).to eq("1")
    end

    it "is 2 if it was bundled with a v2.x version" do
      expect(described_method(lockfile_bundled_with_v2)).to eq("2")
    end

    it "reports the version if it was bundled with a future version" do
      expect(described_method(lockfile_bundled_with_future_version)).to eq("3")
    end
  end

  describe "#combined_dependency_constraints" do
    let(:gemfile_with_bundler) do
      Dependabot::DependencyFile.new(name: "Gemfile", content: <<~GEMFILE)
        source 'https://rubygems.org'
        gem "bundler", "~> 2.3.0"
        gem "rails"
      GEMFILE
    end

    let(:gemspec_with_bundler) do
      Dependabot::DependencyFile.new(name: "example.gemspec", content: <<~GEMSPEC)
        Gem::Specification.new do |spec|
          spec.add_runtime_dependency "bundler", ">= 1.12.0"
          spec.add_dependency "rails", "~> 6.0"
        end
      GEMSPEC
    end

    it "returns constraints for bundler from Gemfile and gemspec files" do
      constraints = described_class.combined_dependency_constraints(
        [gemfile_with_bundler, gemspec_with_bundler],
        "bundler"
      )
      expect(constraints).to contain_exactly("~> 2.3.0", ">= 1.12.0")
    end
  end

  describe "#bundler_dependency_requirement" do
    let(:gemfile_with_bundler) do
      Dependabot::DependencyFile.new(name: "Gemfile", content: <<~GEMFILE)
        source 'https://rubygems.org'
        gem "bundler", "~> 2.3.0"
        gem "rails"
      GEMFILE
    end

    let(:gemspec_with_bundler) do
      Dependabot::DependencyFile.new(name: "example.gemspec", content: <<~GEMSPEC)
        Gem::Specification.new do |spec|
          spec.add_runtime_dependency "bundler", ">= 1.12.0"
          spec.add_dependency "rails", "~> 6.0"
        end
      GEMSPEC
    end

    it "returns a combined requirement for bundler from multiple files" do
      requirement = described_class.bundler_dependency_requirement([gemfile_with_bundler, gemspec_with_bundler])
      expect(requirement.constraints).to eq(["~> 2.3.0", ">= 1.12.0"])
    end

    it "returns nil if no constraints are found" do
      requirement = described_class.bundler_dependency_requirement([])
      expect(requirement).to be_nil
    end
  end
end
