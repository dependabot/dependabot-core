# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/elixir/hex"
require "dependabot/errors"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Elixir::Hex do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: files,
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "plug",
      version: "1.3.0",
      requirements: dependency_requirements,
      package_manager: "hex"
    )
  end

  let(:dependency_requirements) do
    [{ file: "mix.exs", requirement: "~> 1.3.0", groups: [], source: nil }]
  end

  let(:files) { [mixfile, lockfile] }

  let(:mixfile) do
    Dependabot::DependencyFile.new(
      content: mixfile_body,
      name: "mix.exs"
    )
  end

  let(:lockfile) do
    Dependabot::DependencyFile.new(
      content: lockfile_body,
      name: "mix.lock"
    )
  end

  let(:mixfile_body) { fixture("elixir", "mixfiles", "minor_version") }
  let(:lockfile_body) { fixture("elixir", "lockfiles", "minor_version") }

  describe "#latest_version" do
    subject { checker.latest_version }

    let(:hex_url) { "https://hex.pm/api/packages/plug" }
    let(:hex_response) do
      fixture("elixir", "registry_api", "plug_response.json")
    end

    before do
      stub_request(:get, hex_url).
        to_return(status: 200, body: hex_response)
      allow(checker).to receive(:latest_resolvable_version).
        and_return(Gem::Version.new("1.3.5"))
    end

    it { is_expected.to eq(Gem::Version.new("1.4.3")) }

    context "when packagist 404s" do
      before { stub_request(:get, hex_url).to_return(status: 404) }

      it { is_expected.to eq(Gem::Version.new("1.3.5")) }
    end
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { checker.latest_resolvable_version }

    it "returns a non-normalized version, following semver" do
      expect(subject.segments.count).to eq(3)
    end

    it "respects the resolvability of the mix.exs" do
      expect(latest_resolvable_version).
        to be > Gem::Version.new("1.3.5")
      expect(latest_resolvable_version).
        to be < Gem::Version.new("1.4.0")
    end

    context "with a version conflict at the latest version" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "phoenix",
          version: "1.2.1",
          requirements: [
            {
              file: "mix.exs",
              requirement: "== 1.2.1",
              groups: [],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end

      let(:mixfile_body) { fixture("elixir", "mixfiles", "exact_version") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "exact_version") }

      it { is_expected.to eq(Gem::Version.new("1.2.2")) }
    end

    context "when a subdependency needs updating" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "phoenix",
          version: "1.2.5",
          requirements: [
            {
              file: "mix.exs",
              requirement: "~> 1.2.1",
              groups: [],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end

      let(:mixfile_body) { fixture("elixir", "mixfiles", "minor_version") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "minor_version") }

      it { is_expected.to be >= Gem::Version.new("1.3.0") }
    end

    context "with a dependency with a git source" do
      let(:mixfile_body) { fixture("elixir", "mixfiles", "git_source") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "git_source") }

      context "that is not the dependency we're checking" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "plug",
            version: "1.2.0",
            requirements: [
              {
                file: "mix.exs",
                requirement: "1.2.0",
                groups: [],
                source: nil
              }
            ],
            package_manager: "hex"
          )
        end
        it { is_expected.to be >= Gem::Version.new("1.4.3") }
      end
    end

    context "with a dependency with a bad specification" do
      let(:mixfile_body) { fixture("elixir", "mixfiles", "bad_spec") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "exact_version") }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { checker.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a mix.exs that opens another file" do
      let(:mixfile_body) { fixture("elixir", "mixfiles", "loads_file") }
      let(:lockfile_body) { fixture("elixir", "lockfiles", "exact_version") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "phoenix",
          version: "1.2.1",
          requirements: [
            {
              file: "mix.exs",
              requirement: "== 1.2.1",
              groups: [],
              source: nil
            }
          ],
          package_manager: "composer"
        )
      end

      it { is_expected.to eq(Gem::Version.new("1.2.2")) }
    end
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements.first }

    before do
      allow(checker).
        to receive(:latest_resolvable_version).
        and_return(Gem::Version.new("1.6.0"))
    end

    it "delegates to the RequirementsUpdater" do
      expect(described_class::RequirementsUpdater).
        to receive(:new).
        with(
          requirements: dependency_requirements,
          latest_resolvable_version: "1.6.0"
        ).
        and_call_original
      expect(checker.updated_requirements).
        to eq(
          [
            {
              file: "mix.exs",
              requirement: "~> 1.6.0",
              groups: [],
              source: nil
            }
          ]
        )
    end
  end
end
