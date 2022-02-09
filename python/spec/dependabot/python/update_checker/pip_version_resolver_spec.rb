# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/python/update_checker/pip_version_resolver"

RSpec.describe Dependabot::Python::UpdateChecker::PipVersionResolver do
  before do
    stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
  end
  let(:pypi_url) { "https://pypi.org/simple/luigi/" }
  let(:pypi_response) { fixture("pypi", "pypi_simple_response.html") }
  let(:resolver) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: credentials,
      ignored_versions: ignored_versions,
      security_advisories: security_advisories
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
  let(:ignored_versions) { [] }
  let(:security_advisories) { [] }
  let(:dependency_files) { [requirements_file, python_version_file] }
  let(:requirements_file) do
    Dependabot::DependencyFile.new(
      name: "requirements.txt",
      content: fixture("requirements", requirements_fixture_name)
    )
  end
  let(:requirements_fixture_name) { "version_specified.txt" }
  let(:python_version_file) do
    Dependabot::DependencyFile.new(
      name: ".python-version",
      content: python_version_content
    )
  end
  let(:python_version_content) { "3.7.0\n" }
  let(:pypi_response) { fixture("pypi", "pypi_simple_response_django.html") }
  let(:pypi_url) { "https://pypi.org/simple/django/" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: dependency_version,
      requirements: dependency_requirements,
      package_manager: "pip"
    )
  end
  let(:dependency_name) { "django" }
  let(:dependency_version) { "1.2.4" }
  let(:dependency_requirements) do
    [{
      file: "requirements.txt",
      requirement: "==1.2.4",
      groups: [],
      source: nil
    }]
  end

  describe "#latest_resolvable_version" do
    subject { resolver.latest_resolvable_version }

    context "with no indication of the Python version" do
      let(:dependency_files) { [requirements_file] }

      it { is_expected.to eq(Gem::Version.new("3.2.4")) }
    end

    context "with a .python-version file" do
      let(:dependency_files) { [requirements_file, python_version_file] }
      let(:python_version_content) { "3.7.0\n" }

      it { is_expected.to eq(Gem::Version.new("3.2.4")) }

      context "that disallows the latest version" do
        let(:python_version_content) { "3.5.3\n" }
        it { is_expected.to eq(Gem::Version.new("2.2.24")) }
      end
    end
  end

  describe "#latest_resolvable_version_with_no_unlock" do
    subject { resolver.latest_resolvable_version_with_no_unlock }

    it { is_expected.to eq(Gem::Version.new("1.2.4")) }
  end

  describe "#lowest_resolvable_security_fix_version" do
    subject { resolver.lowest_resolvable_security_fix_version }

    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "pip",
          vulnerable_versions: ["<= 2.1.0"]
        )
      ]
    end

    it { is_expected.to eq(Gem::Version.new("2.1.1")) }

    context "with a .python-version file" do
      let(:dependency_files) { [requirements_file, python_version_file] }
      let(:python_version_content) { "3.7.0\n" }

      it { is_expected.to eq(Gem::Version.new("2.1.1")) }

      context "that disallows all fixed versions" do
        let(:python_version_content) { "3.5.3\n" }
        let(:dependency_version) { "3.0.0" }
        let(:dependency_requirements) do
          [{
            file: "requirements.txt",
            requirement: "==3.0.0",
            groups: [],
            source: nil
          }]
        end

        it { is_expected.to be_nil }
      end
    end
  end
end
