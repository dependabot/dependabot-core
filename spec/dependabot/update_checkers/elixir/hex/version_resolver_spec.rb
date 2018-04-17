# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/elixir/hex/version_resolver"

RSpec.describe Dependabot::UpdateCheckers::Elixir::Hex::VersionResolver do
  let(:resolver) do
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
      name: dependency_name,
      version: version,
      requirements: dependency_requirements,
      package_manager: "hex"
    )
  end

  let(:dependency_name) { "plug" }
  let(:version) { "1.3.0" }
  let(:dependency_requirements) do
    [{ file: "mix.exs", requirement: "~> 1.3.0", groups: [], source: nil }]
  end

  let(:files) { [mixfile, lockfile] }
  let(:mixfile) do
    Dependabot::DependencyFile.new(
      name: "mix.exs",
      content: mixfile_fixture_body
    )
  end
  let(:mixfile_fixture_body) do
    fixture("elixir", "mixfiles", mixfile_fixture_name)
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "mix.lock",
      content: fixture("elixir", "lockfiles", lockfile_fixture_name)
    )
  end

  let(:mixfile_fixture_name) { "minor_version" }
  let(:lockfile_fixture_name) { "minor_version" }

  # Prepare the mixfile in the same way the FilePreparer would
  before { mixfile_fixture_body.gsub!("~> 1.3.0", ">= 1.3.0") }

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version }

    it "returns a non-normalized version, following semver" do
      expect(subject.segments.count).to eq(3)
    end

    it "respects the resolvability of the mix.exs" do
      expect(latest_resolvable_version).
        to be > Gem::Version.new("1.3.5")
      expect(latest_resolvable_version).
        to be < Gem::Version.new("1.4.0")
    end

    context "with a dependency with a bad specification" do
      let(:mixfile_fixture_name) { "bad_spec" }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "when the environments for another dependency diverge" do
      # In this example, updating `credo` would add its sub-dependency,
      # `poison`, to the `dev` environment, but the Mixfile explicitly specifies
      # that `poison` should only be available in the `test` environment.
      let(:mixfile_fixture_name) { "diverging_environments" }
      let(:lockfile_fixture_name) { "diverging_environments" }

      let(:dependency_name) { "credo" }
      let(:version) { "0.6.0" }
      let(:dependency_requirements) do
        [{
          file: "mix.exs",
          requirement: "~> 0.6",
          groups: %w(dev test),
          source: nil
        }]
      end

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        # In an ideal world, Dependabot would update the environment specified
        # for `poison` in the Mixfile. In the meantime, though, we just treat
        # this as an impossible-to-update dependency.
        expect(resolver.latest_resolvable_version).to be_nil
      end
    end
  end
end
