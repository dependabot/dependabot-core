# frozen_string_literal: true

require "spec_helper"

require "dependabot/bundler/helpers"

RSpec.describe Dependabot::Bundler::Helpers do
  let(:no_lockfile) { nil }

  let(:lockfile_bundled_with_missing) do
    Dependabot::DependencyFile.new(name: "Gemfile.lock", content: <<~LOCKFILE)
      Mock Gemfile.lock Content Goes Here
    LOCKFILE
  end

  let(:lockfile_bundled_with_v1) do
    Dependabot::DependencyFile.new(name: "Gemfile.lock", content: <<~LOCKFILE)
      Mock Gemfile.lock Content Goes Here

      BUNDLED WITH
        1.17.3
    LOCKFILE
  end

  let(:lockfile_bundled_with_v2) do
    Dependabot::DependencyFile.new(name: "Gemfile.lock", content: <<~LOCKFILE)
      Mock Gemfile.lock Content Goes Here

      BUNDLED WITH
        2.2.11
    LOCKFILE
  end

  let(:lockfile_bundled_with_future_version) do
    Dependabot::DependencyFile.new(name: "Gemfile.lock", content: <<~LOCKFILE)
      Mock Gemfile.lock Content Goes Here

      BUNDLED WITH
        3.9.99
    LOCKFILE
  end

  describe "#bundler_version" do
    def described_method(lockfile)
      described_class.bundler_version(lockfile)
    end

    it "is 2 if there is no lockfile" do
      expect(described_method(no_lockfile)).to eql("2")
    end

    it "is 1 if there is no bundled with string" do
      expect(described_method(lockfile_bundled_with_missing)).to eql("1")
    end

    it "is 1 if it was bundled with a v1.x version" do
      expect(described_method(lockfile_bundled_with_v1)).to eql("1")
    end

    it "is 2 if it was bundled with a v2.x version" do
      expect(described_method(lockfile_bundled_with_v2)).to eql("2")
    end

    it "is 2 if it was bundled with a future version" do
      expect(described_method(lockfile_bundled_with_future_version)).to eql("2")
    end
  end

  describe "#detected_bundler_version" do
    def described_method(lockfile)
      described_class.detected_bundler_version(lockfile)
    end

    it "is unknown if there is no lockfile" do
      expect(described_method(no_lockfile)).to eql("unknown")
    end

    it "is 1 if there is no bundled with string" do
      expect(described_method(lockfile_bundled_with_missing)).to eql("1")
    end

    it "is 1 if it was bundled with a v1.x version" do
      expect(described_method(lockfile_bundled_with_v1)).to eql("1")
    end

    it "is 2 if it was bundled with a v2.x version" do
      expect(described_method(lockfile_bundled_with_v2)).to eql("2")
    end

    it "is 1 if it was bundled with a future version" do
      expect(described_method(lockfile_bundled_with_future_version)).to eql("3")
    end
  end
end
