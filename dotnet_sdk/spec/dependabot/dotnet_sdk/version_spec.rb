# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dotnet_sdk/version"

RSpec.describe Dependabot::DotnetSdk::Version do
  subject(:version) { described_class.new(version_string) }

  describe "#to_s" do
    subject { version.to_s }

    context "with a stable version" do
      let(:version_string) { "11.0.100" }

      it { is_expected.to eq("11.0.100") }
    end

    context "with a preview version" do
      let(:version_string) { "11.0.100-preview.6.26359.118" }

      it { is_expected.to eq("11.0.100-preview.6.26359.118") }
    end

    context "with a release candidate version" do
      let(:version_string) { "9.0.100-rc.1.24452.12" }

      it { is_expected.to eq("9.0.100-rc.1.24452.12") }
    end
  end

  describe "#<=>" do
    it "orders preview versions by their preview number" do
      older = described_class.new("11.0.100-preview.5.26302.115")
      newer = described_class.new("11.0.100-preview.6.26359.118")

      expect(older).to be < newer
    end
  end
end
