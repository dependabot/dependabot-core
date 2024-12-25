# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/version"

RSpec.describe Dependabot::Version do
  subject(:version) { described_class.new(version_string) }

  describe "#lowest_prerelease_suffix" do
    subject(:ignored_versions) { version.lowest_prerelease_suffix }

    let(:version_string) { "1.2.3-alpha.1" }

    it { is_expected.to eq "a" }
  end

  describe "#ignored_major_versions" do
    subject(:ignored_versions) { version.ignored_major_versions }

    let(:version_string) { "1.2.3-alpha.1" }

    it { is_expected.to eq([">= 2.a"]) }
  end

  describe "#ignored_minor_versions" do
    subject(:ignored_versions) { version.ignored_minor_versions }

    let(:version_string) { "1.2.3-alpha.1" }

    it { is_expected.to eq([">= 1.3.a, < 2"]) }
  end

  describe "#ignored_patch_versions" do
    subject(:ignored_versions) { version.ignored_patch_versions }

    let(:version_string) { "1.2.3-alpha.1" }

    it { is_expected.to eq(["> #{version_string}, < 1.3"]) }
  end

  context "when the version string is empty" do
    let(:version_string) { "" }

    it "is equal `0" do
      expect(version.to_s).to eq("0")
    end
  end
end
