# typed: true
# frozen_string_literal: true

require "spec_helper"
require "dependabot/sem_version2"

RSpec.describe Dependabot::SemVersion2 do
  subject(:version) { described_class.new(version_string) }

  let(:valid_versions) do
    %w( 0.0.4 1.2.3 10.20.30 1.1.2-prerelease+meta 1.1.2+meta 1.1.2+meta-valid 1.0.0-alpha
        1.0.0-beta 1.0.0-alpha.beta 1.0.0-alpha.beta.1 1.0.0-alpha.1 1.0.0-alpha0.valid
        1.0.0-alpha.0valid 1.0.0-alpha-a.b-c-somethinglong+build.1-aef.1-its-okay
        1.0.0-rc.1+build.1 2.0.0-rc.1+build.123 1.2.3-beta 10.2.3-DEV-SNAPSHOT
        1.2.3-SNAPSHOT-123 2.0.0+build.1848 2.0.1-alpha.1227 1.0.0-alpha+beta
        1.2.3----RC-SNAPSHOT.12.9.1--.12+788 1.2.3----R-S.12.9.1--.12+meta
        1.2.3----RC-SNAPSHOT.12.9.1--.12 1.0.0+0.build.1-rc.10000aaa-kk-0.1
        9999999.999999999.99999999 1.0.0-0A.is.legal)
  end

  let(:invalid_versions) do
    %w(1 1.2 1.2.3-0123 1.2.3-0123.0123 1.1.2+.123 +invalid -invalid -invalid+invalid -invalid.01 alpha alpha.beta
       alpha.beta.1 alpha.1 alpha+beta alpha_beta alpha. alpha.. beta 1.0.0-alpha_beta -alpha. 1.0.0-alpha..
       1.0.0-alpha..1 1.0.0-alpha...1 1.0.0-alpha....1 1.0.0-alpha.....1 1.0.0-alpha......1 1.0.0-alpha.......1
       01.1.1 1.01.1 1.1.01 1.2.3.DEV 1.2-SNAPSHOT 1.2.31.2.3----RC-SNAPSHOT.12.09.1--..12+788 1.2-RC-SNAPSHOT
       -1.0.3-gamma+b7718 +justmeta 9.8.7+meta+meta 9.8.7-whatever+meta+meta
       999.9999.99999----RC-SNAPSHOT.12.09.1----..12)
  end

  describe "#initialize" do
    it "raises an error when the version is invalid" do
      invalid_versions.each do |version|
        error_msg = "Malformed version number string #{version}"
        expect { described_class.new(version) }.to raise_error(ArgumentError, error_msg)
      end
    end

    context "with an empty version" do
      let(:version_string) { "" }
      let(:error_msg) { "Malformed version number string " }

      it "raises an error" do
        expect { version }.to raise_error(ArgumentError, error_msg)
      end
    end
  end

  describe "to_s" do
    it "returns the correct value" do
      valid_versions.each do |version|
        expect(described_class.new(version).to_s).to eq(version)
      end
    end
  end

  describe "#inspect" do
    subject { described_class.new(version_string).inspect }

    let(:version_string) { "1.0.0+build1" }

    it { is_expected.to eq("#<#{described_class} #{version_string}>") }
  end

  describe "#eql?" do
    let(:first) { described_class.new("1.2.3-rc.1+build1") }
    let(:second) { described_class.new("1.2.3-rc.1+build1") }

    it "returns true for equal semver values" do
      expect(first).to eql(second)
    end
  end

  describe "#<=>" do
    it "sorts version strings semantically" do
      versions = []

      versions << described_class.new("1.0.0-alpha")
      versions << described_class.new("1.0.0-alpha.1")
      versions << described_class.new("1.0.0-alpha.1.beta.gamma")
      versions << described_class.new("1.0.0-alpha.beta")
      versions << described_class.new("1.0.0-alpha.beta.1")
      versions << described_class.new("1.0.0-beta")
      versions << described_class.new("1.0.0-beta.2")
      versions << described_class.new("1.0.0-beta.11")
      versions << described_class.new("1.0.0-rc.1")
      versions << described_class.new("1.0.0")
      expect(versions.shuffle.sort).to eq(versions)
    end

    context "when comparing numerical prereleases" do
      let(:first) { described_class.new("1.0.0-rc.2") }
      let(:second) { described_class.new("1.0.0-rc.10") }

      it "compares numerically" do
        expect(first <=> second).to eq(-1)
        expect(second <=> first).to eq(1)
      end
    end

    context "when comparing numerical prereleases" do
      let(:first) { described_class.new("1.0.0-rc.2") }
      let(:second) { described_class.new("1.0.0-rc.2.1") }

      it "compares numerically" do
        expect(first <=> second).to eq(-1)
        expect(second <=> first).to eq(1)
      end
    end

    context "when the versions are equal" do
      let(:first) { described_class.new("1.0.0-rc.2") }
      let(:second) { described_class.new("1.0.0-rc.2") }

      it "returns 0" do
        expect(first <=> second).to eq(0)
        expect(second <=> first).to eq(0)
      end
    end

    context "when comparing alphanumerical prereleases" do
      let(:first) { described_class.new("1.0.0-alpha10") }
      let(:second) { described_class.new("1.0.0-alpha2") }

      it "compares lexicographically" do
        expect(first <=> second).to eq(-1)
        expect(second <=> first).to eq(1)
      end
    end

    context "when comparing versions that contain build data" do
      let(:first) { described_class.new("1.0.0+build-123") }
      let(:second) { described_class.new("1.0.0+build-456") }

      it "ignores build metadata" do
        expect(first <=> second).to eq(0)
      end
    end
  end

  describe "#prerelease?" do
    subject { version.prerelease? }

    context "with an alpha" do
      let(:version_string) { "1.0.0-alpha" }

      it { is_expected.to be(true) }
    end

    context "with a capitalised alpha" do
      let(:version_string) { "1.0.0-Alpha" }

      it { is_expected.to be(true) }
    end

    context "with a dev token" do
      let(:version_string) { "1.2.1-dev-65" }

      it { is_expected.to be(true) }
    end

    context "with a 'pre' pre-release separated with a -" do
      let(:version_string) { "2.10.0-pre0" }

      it { is_expected.to be(true) }
    end

    context "with a release" do
      let(:version_string) { "1.0.0" }

      it { is_expected.to be(false) }
    end

    context "with a + separated alphanumeric build identifier" do
      let(:version_string) { "1.0.0+build1" }

      it { is_expected.to be(false) }
    end

    context "with an 'alpha' separated by a -" do
      let(:version_string) { "1.0.0-alpha+001" }

      it { is_expected.to be(true) }
    end
  end

  describe ".correct?" do
    subject { described_class.correct?(version_string) }

    context "with a nil version" do
      let(:version_string) { nil }

      it { is_expected.to be(false) }
    end

    context "with an empty version" do
      let(:version_string) { "" }

      it { is_expected.to be(false) }
    end

    context "with valid semver2 strings" do
      it "returns true" do
        valid_versions.each do |version|
          expect(described_class.correct?(version)).to be(true)
        end
      end
    end

    context "with invalid semver2 strings" do
      it "returns false" do
        invalid_versions.each do |version|
          expect(described_class.correct?(version)).to be(false)
        end
      end
    end
  end
end
