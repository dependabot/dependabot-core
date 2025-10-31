# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/python/update_checker/library_detector"

RSpec.describe Dependabot::Python::UpdateChecker::LibraryDetector do
  let(:detector) { described_class.new(dependency_files: dependency_files) }
  let(:dependency_files) { [pyproject] }
  let(:pyproject) do
    Dependabot::DependencyFile.new(
      name: "pyproject.toml",
      content: fixture("pyproject_files", pyproject_fixture_name)
    )
  end

  describe "#library?" do
    subject(:is_library) { detector.library? }

    context "with Poetry legacy format" do
      let(:pyproject_fixture_name) { "tilde_version.toml" }

      context "when project matches PyPI" do
        before do
          stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
            .to_return(
              status: 200,
              body: fixture("pypi", "pypi_response_pendulum.json")
            )
        end

        it { is_expected.to be true }
      end

      context "when project doesn't match PyPI" do
        before do
          stub_request(:get, "https://pypi.org/pypi/pendulum/json/")
            .to_return(status: 404)
        end

        it { is_expected.to be false }
      end
    end

    context "with Poetry 2 PEP 621 format" do
      let(:pyproject_fixture_name) { "poetry_v2_pep621.toml" }

      context "when project doesn't match PyPI" do
        before do
          stub_request(:get, "https://pypi.org/pypi/example-project/json/")
            .to_return(status: 404)
        end

        it { is_expected.to be false }
      end

      context "when project description doesn't match" do
        before do
          stub_request(:get, "https://pypi.org/pypi/example-project/json/")
            .to_return(
              status: 200,
              body: {
                info: {
                  name: "example-project",
                  summary: "Different description"
                }
              }.to_json
            )
        end

        it { is_expected.to be false }
      end
    end

    context "with standard PEP 621 format (non-Poetry)" do
      let(:pyproject_fixture_name) { "standard_python.toml" }

      context "when project matches PyPI" do
        before do
          stub_request(:get, "https://pypi.org/pypi/pkgtest/json/")
            .to_return(
              status: 200,
              body: {
                info: {
                  name: "pkgtest",
                  summary: "A test package"
                }
              }.to_json
            )
        end

        it { is_expected.to be false }
      end
    end

    context "without pyproject.toml" do
      let(:dependency_files) { [] }

      it { is_expected.to be false }
    end

    context "with missing name" do
      let(:pyproject_fixture_name) { "poetry_non_package_mode.toml" }

      it { is_expected.to be false }
    end
  end
end
