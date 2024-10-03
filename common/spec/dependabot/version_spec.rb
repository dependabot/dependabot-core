# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/version"

RSpec.describe Dependabot::Version do
  subject(:version) { described_class.new(version_string) }

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
end
