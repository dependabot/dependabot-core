# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/terraform/version"

RSpec.describe Dependabot::Terraform::Version do
  subject(:version) { described_class.new(version_string) }

  let(:version_string) { "1.0.0" }

  describe "#to_s" do
    subject { version.to_s }

    context "with a non-prerelease" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to eq "1.0.0" }
    end

    context "with a normal prerelease" do
      let(:version_string) { "1.0.0.pre1" }

      it { is_expected.to eq "1.0.0.pre1" }
    end

    context "with a Terraform-style prerelease" do
      let(:version_string) { "1.0.0-pre1" }

      it { is_expected.to eq "1.0.0-pre1" }
    end
  end

  describe "#correct?" do
    subject { described_class.correct?(version_string) }

    valid = %w(1.0.0 v0.3.2 1.17.2+backport-1)
    valid.each do |version|
      context "with version #{version}" do
        let(:version_string) { version }

        it { is_expected.to be(true) }
      end
    end

    invalid = ["", nil]
    invalid.each do |version|
      context "with version #{version}" do
        let(:version_string) { version }

        it { is_expected.to be(false) }
      end
    end
  end
end
