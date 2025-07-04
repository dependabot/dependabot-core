# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/update_checker/pdm_version_resolver"

namespace = Dependabot::Python::UpdateChecker
RSpec.describe namespace::PdmVersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      repo_contents_path: nil
    )
  end

  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end
  let(:dependency_files) { [pyproject, lockfile] }
  let(:pyproject) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: pyproject_content
    )
  end
  let(:pyproject_content) { fixture("projects/pdm", "pyproject.toml") }
  let(:lockfile) do
    Dependabot::DependencyFile.new(
      name: "pdm.lock",
      content: fixture("projects/pdm", "pdm.lock")
    )
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "pip"
    )
  end
  let(:dependency_name) { "requests" }
  let(:dependency_version) { "2.25.0" }
  let(:dependency_groups) { [] }
  let(:dependency_requirements) do
    [{
      file: "pyproject.toml",
      requirement: "~=2.25",
      groups: dependency_groups,
      source: nil
    }]
  end

  describe "#latest_resolvable_version" do
    subject(:latest_resolvable_version) { resolver.latest_resolvable_version(requirement: updated_requirement) }

    let(:updated_requirement) { ">=2.25.0,<=2.28.0" }

    context "without a lockfile (but with a latest version)" do
      let(:dependency_files) { [pyproject] }
      let(:dependency_version) { nil }

      it { is_expected.to eq(Gem::Version.new("2.28.0")) }
    end

    context "with a dependency defined under PEP 621 project dependencies" do
      let(:pyproject_fixture_name) { "pep621_exact_requirement.toml" }

      it { is_expected.to eq(Gem::Version.new("2.28.0")) }
    end

    context "with a dependency defined under optional-dependencies" do
      let(:pyproject_content) do
        <<~TOML
          [project]
          name = "demo"
          version = "0.1.0"

          [project.optional-dependencies]
          lint = [
              "requests~=2.25",
          ]
        TOML
      end

      let(:dependency_groups) { ["lint"] }

      it { is_expected.to eq(Gem::Version.new("2.28.0")) }
    end

    context "with a lockfile" do
      let(:dependency_files) { [pyproject, lockfile] }
      let(:dependency_version) { "2.25.0" }

      it { is_expected.to eq(Gem::Version.new("2.28.0")) }

      context "when not unlocking the requirement" do
        let(:updated_requirement) { "==2.25.0" }

        it { is_expected.to eq(Gem::Version.new("2.25.0")) }
      end
    end

    context "when the latest version isn't allowed" do
      let(:updated_requirement) { ">=2.25.0,<=2.27.0" }

      it { is_expected.to eq(Gem::Version.new("2.27.0")) }
    end

    context "when the latest version is nil" do
      let(:updated_requirement) { ">=2.25.0" }

      it { is_expected.to be >= Gem::Version.new("2.28.0") }
    end

    context "with a subdependency" do
      let(:dependency_name) { "idna" }
      let(:dependency_version) { "3.3" }
      let(:dependency_requirements) { [] }
      let(:updated_requirement) { ">=3.3,<=3.4" }

      # Resolution blocked by requests
      it { is_expected.to eq(Gem::Version.new("3.4")) }

      context "when dependency shouldn't be in the lockfile at all" do
        let(:dependency_name) { "cryptography" }
        let(:dependency_version) { "3.4.8" }
        let(:dependency_requirements) { [] }
        let(:updated_requirement) { ">=3.4.8,<=38.0.0" }

        # Ideally we would ignore sub-dependencies that shouldn't be in the
        # lockfile, but determining that is hard. It's fine for us to update
        # them instead - they'll be removed in another (unrelated) PR
        it { is_expected.to eq(Gem::Version.new("38.0.0")) }
      end
    end

    context "when version is not resolvable" do
      let(:dependency_files) { [pyproject] }
      let(:updated_requirement) { ">=99.0.0" }

      it "raises a helpful error" do
        expect { latest_resolvable_version }
          .to raise_error(Dependabot::DependencyFileNotResolvable) do |error|
            expect(error.message)
              .to include("Unable to find a resolution") || include("ResolutionError")
          end
      end
    end
  end

  describe "#resolvable?" do
    subject(:resolvable) { resolver.resolvable?(version: version) }

    let(:version) { Gem::Version.new("2.28.0") }

    context "when version is resolvable" do
      it { is_expected.to be(true) }

      context "with a subdependency" do
        let(:dependency_name) { "idna" }
        let(:dependency_version) { "3.3" }
        let(:dependency_requirements) { [] }
        let(:version) { Gem::Version.new("3.4") }

        it { is_expected.to be(true) }
      end
    end

    context "when version is not resolvable" do
      let(:version) { Gem::Version.new("99.28.0") }

      it { is_expected.to be(false) }

      context "with a subdependency" do
        let(:dependency_name) { "idna" }
        let(:dependency_version) { "3.3" }
        let(:dependency_requirements) { [] }
        let(:version) { Gem::Version.new("99.0") }

        it { is_expected.to be(false) }
      end

      context "when the original manifest isn't resolvable" do
        let(:dependency_files) { [pyproject] }
        let(:pyproject_content) do
          <<~TOML
            [project]
            name = "demo"
            version = "0.1.0"
            dependencies = [
                "black==99.0.0",  # Non-existent version
                "requests~=2.25.0"
            ]
          TOML
        end

        it { is_expected.to be(false) }
      end
    end
  end
end
