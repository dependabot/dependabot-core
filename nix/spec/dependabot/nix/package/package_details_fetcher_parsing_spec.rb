# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nix/package/package_details_fetcher"

RSpec.describe Dependabot::Nix::Package::PackageDetailsFetcher do
  extend T::Sig

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Nix::Package::PackageDetailsFetcher) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  let(:fetcher) { described_class.new(dependency: dependency, credentials: []) }

  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "nixpkgs",
      version: "locked",
      requirements: [{
        file: "flake.lock",
        requirement: nil,
        groups: [],
        source: { type: "git", url: "https://github.com/NixOS/nixpkgs", branch: nil, ref: ref }
      }],
      package_manager: "nix"
    )
  end

  sig { returns(String) }
  let(:ref) { "nixos-unstable" }

  sig { returns(String) }
  let(:response) { [{ "after" => 42, "timestamp" => "invalid" }].to_json }
  # rubocop:enable RSpec/ScatteredLet

  context "with activity results" do
    before do
      stub_request(:get, %r{\Ahttps://api\.github\.com/repos/NixOS/nixpkgs/activity\?})
        .to_return(status: 200, body: response, headers: { "Content-Type" => "application/json" })
    end

    it "does not turn a malformed revision into a fallback or empty release list" do
      expect(Dependabot::GitCommitChecker).not_to receive(:new)

      expect { fetcher.available_versions }
        .to raise_error(Dependabot::PrivateSourceBadResponse, /activity.*after/)
    end

    context "with an invalid optional timestamp" do
      sig { returns(String) }
      let(:response) { [{ "after" => "new", "before" => "locked", "timestamp" => "invalid" }].to_json }

      it "keeps the revisions without a release date" do
        versions = fetcher.available_versions

        expect(versions.map(&:tag)).to eq(%w(new locked))
        expect(versions.map(&:released_at)).to eq([nil, nil])
      end
    end
  end

  context "with commit history results" do
    # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
    sig { returns(String) }
    let(:ref) { "v1.0.0" }

    sig { returns(String) }
    let(:response) do
      [
        { "sha" => "new", "commit" => { "committer" => { "date" => "invalid" } } },
        { "sha" => "locked", "commit" => { "committer" => { "date" => "2026-10-01T00:00:00Z" } } },
        { "sha" => 42, "commit" => false }
      ].to_json
    end
    # rubocop:enable RSpec/ScatteredLet

    before do
      checker = instance_double(
        Dependabot::GitCommitChecker,
        ref_details_for_pinned_ref: Excon::Response.new(status: 200, body: response)
      )
      allow(Dependabot::GitCommitChecker).to receive(:new).and_return(checker)
    end

    it "parses only the selected history through the locked revision" do
      versions = fetcher.available_versions

      expect(versions.map(&:tag)).to eq(%w(new locked))
      expect(versions.map(&:released_at)).to eq([nil, Time.utc(2026, 10, 1)])
    end

    context "with a malformed selected revision" do
      sig { returns(String) }
      let(:response) { [{ "sha" => 42 }].to_json }

      it "reports a contextual response error instead of constructing an invalid release" do
        expect { fetcher.available_versions }
          .to raise_error(Dependabot::PrivateSourceBadResponse, /commit.*sha/)
      end
    end
  end
end
