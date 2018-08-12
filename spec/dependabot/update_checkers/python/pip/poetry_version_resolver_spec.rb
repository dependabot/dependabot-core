# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/python/pip/poetry_version_resolver"

namespace = Dependabot::UpdateCheckers::Python::Pip
RSpec.describe namespace::PoetryVersionResolver do
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      unlock_requirement: unlock_requirement,
      latest_allowable_version: latest_version
    )
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:unlock_requirement) { true }
  let(:dependency_files) { [pyproject, pyproject_lock] }
  let(:latest_version) { Gem::Version.new("2.18.4") }
  let(:pyproject) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: fixture("python", "pyproject_files", pyproject_fixture_name)
    )
  end
  let(:pyproject_fixture_name) { "exact_version.toml" }
  let(:pyproject_lock) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: fixture("python", "lockfiles", lockfile_fixture_name)
    )
  end
  let(:lockfile_fixture_name) { "exact_version.lock" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "pip"
    )
  end
  let(:dependency_name) { "requests" }
  let(:dependency_version) { "2.18.0" }
  let(:dependency_requirements) do
    [{
      file: "pyproject.toml",
      requirement: "2.18.0",
      groups: ["dependencies"],
      source: nil
    }]
  end

  describe "#latest_resolvable_version" do
    subject { resolver.latest_resolvable_version }

    context "with a lockfile" do
      let(:dependency_files) { [pyproject, pyproject_lock] }
      let(:dependency_version) { "2.18.0" }
      it { is_expected.to eq(Gem::Version.new("2.18.4")) }

      context "when not unlocking the requirement" do
        let(:unlock_requirement) { false }
        it { is_expected.to eq(Gem::Version.new("2.18.0")) }
      end
    end

    context "without a lockfile (but with a latest version)" do
      let(:dependency_files) { [pyproject] }
      let(:dependency_version) { nil }
      it { is_expected.to eq(Gem::Version.new("2.18.4")) }
    end

    context "when the latest version isn't allowed" do
      let(:latest_version) { Gem::Version.new("2.18.3") }
      it { is_expected.to eq(Gem::Version.new("2.18.3")) }
    end

    context "when the latest version is nil" do
      let(:latest_version) { nil }
      it { is_expected.to be >= Gem::Version.new("2.19.0") }
    end

    context "with a subdependency" do
      let(:dependency_name) { "idna" }
      let(:dependency_version) { "2.5" }
      let(:dependency_requirements) { [] }
      let(:latest_version) { Gem::Version.new("2.7") }

      # Resolution blocked by requests
      it { is_expected.to eq(Gem::Version.new("2.5")) }
    end

    context "with a conflict at the latest version" do
      let(:pyproject_fixture_name) { "conflict_at_latest.toml" }
      let(:lockfile_fixture_name) { "conflict_at_latest.lock" }
      let(:dependency_version) { "2.6.0" }
      let(:dependency_requirements) do
        [{
          file: "pyproject.toml",
          requirement: "2.6.0",
          groups: ["dependencies"],
          source: nil
        }]
      end

      # Conflict with chardet is introduced in v2.16.0
      it { is_expected.to eq(Gem::Version.new("2.15.1")) }
    end
  end
end
