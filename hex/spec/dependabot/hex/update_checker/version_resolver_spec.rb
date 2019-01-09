# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/hex/update_checker/version_resolver"

RSpec.describe Dependabot::Hex::UpdateChecker::VersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      prepared_dependency_files: prepared_files,
      original_dependency_files: original_files,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com",
        "username" => "x-access-token",
        "password" => "token"
      }]
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

  let(:original_files) { [mixfile, lockfile] }
  let(:prepared_files) { [mixfile, lockfile] }
  let(:mixfile) do
    Dependabot::DependencyFile.new(
      name: "mix.exs",
      content: mixfile_fixture_body
    )
  end
  let(:mixfile_fixture_body) { fixture("mixfiles", mixfile_fixture_name) }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "mix.lock",
      content: fixture("lockfiles", lockfile_fixture_name)
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

      it "raises a Dependabot::DependencyFileNotResolvable error",
         skip_ci: true do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with an unresolvable mixfile" do
      let(:mixfile_fixture_name) { "unresolvable" }

      it "raises a Dependabot::DependencyFileNotResolvable error" do
        expect { resolver.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "with a mix.exs that generates a deps warnings" do
      let(:mixfile_fixture_name) { "deps_warning" }

      it "respects the resolvability of the mix.exs" do
        expect(latest_resolvable_version).
          to be > Gem::Version.new("1.3.5")
        expect(latest_resolvable_version).
          to be < Gem::Version.new("1.4.0")
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

    context "without a lockfile" do
      it "respects the resolvability of the mix.exs" do
        expect(latest_resolvable_version).
          to be > Gem::Version.new("1.3.5")
        expect(latest_resolvable_version).
          to be < Gem::Version.new("1.4.0")
      end

      context "with a mix.exs that has caused trouble in the past" do
        let(:files) { [mixfile] }
        let(:mixfile_fixture_name) { "coxir" }
        let(:dependency_name) { "kcl" }
        let(:version) { nil }
        let(:dependency_requirements) do
          [{ file: "mix.exs", requirement: "~> 1.1", groups: [], source: nil }]
        end

        it "resolves without issue" do
          expect(latest_resolvable_version).to be >= Gem::Version.new("1.1.0")
        end
      end
    end
  end
end
