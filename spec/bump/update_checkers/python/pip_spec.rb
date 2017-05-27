# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/update_checkers/python/pip"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Bump::UpdateCheckers::Python::Pip do
  it_behaves_like "an update checker"

  before do
    stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
  end
  let(:pypi_url) { "https://pypi.python.org/pypi/luigi/json" }
  let(:pypi_response) { fixture("python", "pypi_response.json") }

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [],
      github_access_token: "token"
    )
  end

  let(:dependency) do
    Bump::Dependency.new(
      name: "luigi",
      version: "2.0.0",
      package_manager: "pip"
    )
  end

  describe "#needs_update?" do
    subject { checker.needs_update? }

    context "given an outdated dependency" do
      it { is_expected.to be_truthy }
    end

    context "given an up-to-date dependency" do
      let(:dependency) do
        Bump::Dependency.new(
          name: "luigi",
          version: "2.6.0",
          package_manager: "pip"
        )
      end
      it { is_expected.to be_falsey }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq(Gem::Version.new("2.6.0")) }

    context "when the pypi link resolves to a redirect" do
      let(:redirect_url) { "https://pypi.python.org/pypi/LuiGi/json" }

      before do
        stub_request(:get, pypi_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(status: 200, body: pypi_response)
      end

      it { is_expected.to eq(Gem::Version.new("2.6.0")) }
    end
  end

  describe "#updated_dependency" do
    subject { checker.updated_dependency }
    it "returns an instance of Dependency" do
      expect(subject.name).to eq("luigi")
      expect(subject.version).to eq("2.6.0")
      expect(subject.previous_version).to eq("2.0.0")
      expect(subject.package_manager).to eq("pip")
    end
  end
end
