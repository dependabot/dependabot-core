# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/python/pip/pip_compile_version_resolver"

namespace = Dependabot::UpdateCheckers::Python::Pip
RSpec.describe namespace::PipCompileVersionResolver do
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
  let(:latest_version) { Gem::Version.new("18.1.0") }
  let(:dependency_files) { [manifest_file, generated_file] }
  let(:manifest_file) do
    Dependabot::DependencyFile.new(
      name: "requirements/test.in",
      content: fixture("python", "pip_compile_files", manifest_fixture_name)
    )
  end
  let(:generated_file) do
    Dependabot::DependencyFile.new(
      name: "requirements/test.txt",
      content: fixture("python", "requirements", generated_fixture_name)
    )
  end
  let(:manifest_fixture_name) { "unpinned.in" }
  let(:generated_fixture_name) { "pip_compile_unpinned.txt" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "pip"
    )
  end
  let(:dependency_name) { "attrs" }
  let(:dependency_version) { "17.3.0" }
  let(:dependency_requirements) do
    [{
      file: "requirements/test.in",
      requirement: nil,
      groups: [],
      source: nil
    }]
  end

  describe "#latest_resolvable_version" do
    subject { resolver.latest_resolvable_version }

    it { is_expected.to be >= Gem::Version.new("18.1.0") }

    context "with an upper bound" do
      let(:manifest_fixture_name) { "bounded.in" }
      let(:generated_fixture_name) { "pip_compile_bounded.txt" }
      let(:dependency_requirements) do
        [{
          file: "requirements/test.in",
          requirement: "<=17.4.0",
          groups: [],
          source: nil
        }]
      end

      it { is_expected.to be >= Gem::Version.new("18.1.0") }

      context "when not unlocking requirements" do
        let(:unlock_requirement) { false }
        it { is_expected.to eq(Gem::Version.new("17.4.0")) }
      end

      context "when the latest version isn't allowed" do
        let(:latest_version) { Gem::Version.new("18.0.0") }
        it { is_expected.to eq(Gem::Version.new("17.4.0")) }
      end
    end

    context "with a Python 2.7 library" do
      let(:manifest_fixture_name) { "legacy_python.in" }
      let(:generated_fixture_name) { "pip_compile_legacy_python.txt" }

      let(:dependency_name) { "wsgiref" }
      let(:dependency_version) { "0.1.1" }
      let(:dependency_requirements) do
        [{
          file: "requirements/test.in",
          requirement: "<=0.1.2",
          groups: [],
          source: nil
        }]
      end

      it { is_expected.to eq(Gem::Version.new("0.1.2")) }
    end
  end
end
