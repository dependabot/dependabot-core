# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/metadata_finder"

RSpec.describe Dependabot::Conda::MetadataFinder do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.0.0",
      requirements: [{
        file: "environment.yml",
        requirement: "=1.0.0",
        groups: [],
        source: nil
      }],
      package_manager: "conda"
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
  let(:metadata_finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  describe "#source" do
    context "when dependency is a Python package" do
      let(:dependency_name) { "numpy" }

      it "returns nil for Python packages" do
        expect(metadata_finder.source).to be_nil
      end
    end

    context "when dependency is not a Python package" do
      let(:dependency_name) { "git" }

      it "returns nil for non-Python packages" do
        expect(metadata_finder.source).to be_nil
      end
    end

    context "when dependency is cmake (non-Python package)" do
      let(:dependency_name) { "cmake" }

      it "returns nil for cmake" do
        expect(metadata_finder.source).to be_nil
      end
    end

    context "when dependency is requests (Python package)" do
      let(:dependency_name) { "requests" }

      it "returns nil for requests" do
        expect(metadata_finder.source).to be_nil
      end
    end
  end

  describe "#python_package?" do
    let(:dependency_name) { "numpy" }

    it "delegates to PythonPackageClassifier" do
      expect(Dependabot::Conda::PythonPackageClassifier)
        .to receive(:python_package?)
        .with("numpy")
        .and_return(true)

      expect(metadata_finder.send(:python_package?, "numpy")).to be(true)
    end
  end
end
