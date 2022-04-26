# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/version"

RSpec.describe Dependabot::NpmAndYarn::Version do
  subject(:version) { described_class.new(version_string) }
  let(:version_string) { "1.0.0" }

  describe ".correct?" do
    subject { described_class.correct?(version_string) }

    context "with a string prefixed with a 'v'" do
      let(:version_string) { "v1.0.0" }
      it { is_expected.to eq(true) }
    end

    context "with a string not prefixed with a 'v'" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq(true) }
    end

    context "with build metadata" do
      let(:version_string) { "1.0.0+some-metadata" }
      it { is_expected.to eq(true) }
    end

    context "with an invalid string" do
      let(:version_string) { "va1.0.0" }
      it { is_expected.to eq(false) }
    end
  end

  describe ".new" do
    subject { described_class.new(version_string) }

    context "with a version class" do
      let(:version_string) { described_class.new("1.0.0") }
      it { is_expected.to eq(described_class.new("1.0.0")) }
    end
  end

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

    context "with a JS-style prerelease" do
      let(:version_string) { "1.0.0-pre1" }
      it { is_expected.to eq "1.0.0-pre1" }
    end

    context "with build metadata" do
      let(:version_string) { "1.0.0+some-metadata" }
      it { is_expected.to eq "1.0.0+some-metadata" }
    end
  end

  describe "#major" do
    subject { version.major }

    context "with major, minor, patch, and prerelease" do
      let(:version_string) { "1.2.3.pre1" }
      it { is_expected.to eq 1 }
    end

    context "with major, minor, and patch" do
      let(:version_string) { "1.2.3" }
      it { is_expected.to eq 1 }
    end

    context "with major and minor" do
      let(:version_string) { "1.2" }
      it { is_expected.to eq 1 }
    end

    context "with major" do
      let(:version_string) { "1" }
      it { is_expected.to eq 1 }
    end

    context "with blank" do
      let(:version_string) { "" }
      it { is_expected.to eq 0 }
    end
  end

  describe "#minor" do
    subject { version.minor }

    context "with major, minor, patch, and prerelease" do
      let(:version_string) { "1.2.3.pre1" }
      it { is_expected.to eq 2 }
    end

    context "with major, minor, and patch" do
      let(:version_string) { "1.2.3" }
      it { is_expected.to eq 2 }
    end

    context "with major and minor" do
      let(:version_string) { "1.2" }
      it { is_expected.to eq 2 }
    end

    context "with major" do
      let(:version_string) { "1" }
      it { is_expected.to eq 0 }
    end

    context "with blank" do
      let(:version_string) { "" }
      it { is_expected.to eq 0 }
    end
  end

  describe "#patch" do
    subject { version.patch }

    context "with major, minor, patch, and prerelease" do
      let(:version_string) { "1.2.3.pre1" }
      it { is_expected.to eq 3 }
    end

    context "with major, minor, and patch" do
      let(:version_string) { "1.2.3" }
      it { is_expected.to eq 3 }
    end

    context "with major and minor" do
      let(:version_string) { "1.2" }
      it { is_expected.to eq 0 }
    end

    context "with major" do
      let(:version_string) { "1" }
      it { is_expected.to eq 0 }
    end

    context "with blank" do
      let(:version_string) { "" }
      it { is_expected.to eq 0 }
    end
  end

  describe "#backwards_compatible_with?" do
    subject { version.backwards_compatible_with?(other_version) }
    let(:other_version) { described_class.new(other_version_string) }

    context "comparing same version" do
      let(:version_string) { "1.2.3.pre1" }
      let(:other_version_string) { version_string }

      it { is_expected.to eq true }
    end

    context "comparing same version with different prerelease" do
      let(:version_string) { "1.2.3.pre1" }
      let(:other_version_string) { "1.2.3.pre2" }

      it { is_expected.to eq true }
    end

    context "comparing version with later patch" do
      let(:version_string) { "1.2.3" }
      let(:other_version_string) { "1.2.4" }

      it { is_expected.to eq true }
    end

    context "comparing version with earlier patch" do
      let(:version_string) { "1.2.3" }
      let(:other_version_string) { "1.2.2" }

      it { is_expected.to eq true }
    end

    context "comparing version with zero patch" do
      let(:version_string) { "1.2.3" }
      let(:other_version_string) { "1.2.0" }

      it { is_expected.to eq true }
    end

    context "comparing version with omitted patch" do
      let(:version_string) { "1.2.3" }
      let(:other_version_string) { "1.2" }

      it { is_expected.to eq true }
    end

    context "comparing version with earlier minor" do
      let(:version_string) { "1.2.3" }
      let(:other_version_string) { "1.1" }

      it { is_expected.to eq true }
    end

    context "comparing version with later minor" do
      let(:version_string) { "1.2.3" }
      let(:other_version_string) { "1.3" }

      it { is_expected.to eq false }
    end

    context "comparing version with earlier major" do
      let(:version_string) { "2.3.4" }
      let(:other_version_string) { "1.2.3" }

      it { is_expected.to eq false }
    end

    context "comparing version with later major" do
      let(:version_string) { "1.2.3" }
      let(:other_version_string) { "2.3.4" }

      it { is_expected.to eq false }
    end

    context "comparing same versions with zero major" do
      let(:version_string) { "0.2.1" }
      let(:other_version_string) { "0.2.1" }

      it { is_expected.to eq true }
    end

    context "comparing earlier version with zero major" do
      let(:version_string) { "0.2.1" }
      let(:other_version_string) { "0.2.0" }

      it { is_expected.to eq false }
    end

    context "comparing later version with zero major" do
      let(:version_string) { "0.2.1" }
      let(:other_version_string) { "0.2.2" }

      it { is_expected.to eq false }
    end
  end

  describe "compatibility with Gem::Requirement" do
    subject { requirement.satisfied_by?(version) }
    let(:requirement) { Gem::Requirement.new(">= 1.0.0") }

    context "with a greater version" do
      let(:version_string) { "1.0.0" }
      it { is_expected.to eq(true) }
    end

    context "with an lesser version" do
      let(:version_string) { "0.9.0" }
      it { is_expected.to eq(false) }
    end

    context "with a valid prerelease version" do
      let(:version_string) { "1.1.0-pre" }
      it { is_expected.to eq(true) }
    end

    context "prefixed with a 'v'" do
      context "with a greater version" do
        let(:version_string) { "v1.1.0" }
        it { is_expected.to eq(true) }
      end

      context "with an lesser version" do
        let(:version_string) { "v0.9.0" }
        it { is_expected.to eq(false) }
      end
    end

    context "with build metadata" do
      let(:requirement) { Gem::Requirement.new("1.0.0") }
      let(:version_string) { "1.0.0+build-metadata" }

      it { is_expected.to eq(true) }
    end
  end
end
