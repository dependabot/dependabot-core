# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/opam/update_checker"
require "dependabot/opam/version"

RSpec.describe Dependabot::Opam::UpdateChecker do
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      raise_on_ignored: raise_on_ignored
    )
  end
  let(:dependency_files) { [] }
  let(:credentials) { [] }
  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "opam"
    )
  end
  let(:dependency_name) { "lwt" }
  let(:dependency_version) { nil }
  let(:dependency_requirements) do
    [{
      file: "example.opam",
      requirement: ">= \"5.0.0\"",
      groups: [],
      source: nil
    }]
  end

  describe "#can_update?" do
    subject { checker.can_update?(requirements_to_unlock: :own) }

    context "when a newer version is available" do
      before do
        stub_request(:get, "https://opam.ocaml.org/packages/lwt/")
          .to_return(status: 200, body: lwt_package_list)
      end

      let(:lwt_package_list) do
        <<~HTML
          <a href="lwt.5.7.0/">lwt.5.7.0</a>
          <a href="lwt.5.8.0/">lwt.5.8.0</a>
        HTML
      end

      it { is_expected.to be true }
    end

    context "when already at latest version" do
      let(:dependency_version) { "5.8.0" }
      let(:lwt_package_list) do
        <<~HTML
          <a href="lwt.5.7.0/">lwt.5.7.0</a>
          <a href="lwt.5.8.0/">lwt.5.8.0</a>
        HTML
      end

      before do
        stub_request(:get, "https://opam.ocaml.org/packages/lwt/")
          .to_return(status: 200, body: lwt_package_list)
      end

      it { is_expected.to be false }
    end
  end

  describe "#latest_version" do
    subject(:latest_version) { checker.latest_version }

    before do
      stub_request(:get, "https://opam.ocaml.org/packages/#{dependency_name}/")
        .to_return(status: 200, body: package_list)
    end

    context "with multiple versions available" do
      let(:package_list) do
        <<~HTML
          <a href="lwt.5.5.0/">lwt.5.5.0</a>
          <a href="lwt.5.6.0/">lwt.5.6.0</a>
          <a href="lwt.5.7.0/">lwt.5.7.0</a>
        HTML
      end

      it "returns the highest version" do
        expect(latest_version).to eq(Dependabot::Opam::Version.new("5.7.0"))
      end
    end

    context "with pre-release versions" do
      let(:package_list) do
        <<~HTML
          <a href="lwt.5.7.0/">lwt.5.7.0</a>
          <a href="lwt.5.8.0~beta1/">lwt.5.8.0~beta1</a>
        HTML
      end

      it "includes pre-release versions (Debian ~ sorts after digits)" do
        # In Debian versioning, 5.8.0~beta1 > 5.7.0 because 5.8.0 > 5.7.0
        # The ~ only affects comparison within the same version (5.8.0~beta < 5.8.0)
        expect(latest_version).to eq(Dependabot::Opam::Version.new("5.8.0~beta1"))
      end
    end

    context "with no versions available" do
      let(:package_list) { "" }

      it "returns nil" do
        expect(latest_version).to be_nil
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    before do
      stub_request(:get, "https://opam.ocaml.org/packages/#{dependency_name}/")
        .to_return(status: 200, body: package_list)
    end

    let(:package_list) do
      <<~HTML
        <a href="dune.2.9.0/">dune.2.9.0</a>
        <a href="dune.3.0.0/">dune.3.0.0</a>
        <a href="dune.3.5.0/">dune.3.5.0</a>
      HTML
    end
    let(:dependency_name) { "dune" }
    let(:dependency_requirements) do
      [{
        file: "example.opam",
        requirement: ">= \"2.0\" & < \"3.0\"",
        groups: [],
        source: nil
      }]
    end

    it "returns highest version matching constraints" do
      # Constraint is >= "2.0" & < "3.0", so should return 2.9.0, not 3.5.0
      expect(latest_resolvable_version).to eq(Dependabot::Opam::Version.new("2.9.0"))
    end
  end

  describe "#updated_requirements" do
    subject(:updated_requirements) { checker.updated_requirements }

    let(:dependency_requirements) do
      [{
        file: "example.opam",
        requirement: ">= \"5.0.0\"",
        groups: [],
        source: nil
      }]
    end
    let(:lwt_versions) do
      <<~HTML
        <a href="lwt.5.7.0/">lwt.5.7.0</a>
        <a href="lwt.5.8.0/">lwt.5.8.0</a>
      HTML
    end

    before do
      stub_request(:get, "https://opam.ocaml.org/packages/lwt/")
        .to_return(status: 200, body: lwt_versions)

      allow(checker).to receive(:latest_version)
        .and_return(Dependabot::Opam::Version.new("5.8.0"))
    end

    it "updates requirement to new version" do
      expect(updated_requirements).to eq(
        [{
          file: "example.opam",
          requirement: ">= 5.8.0",
          groups: [],
          source: nil
        }]
      )
    end
  end
end
