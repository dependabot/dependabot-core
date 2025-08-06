# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

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

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    context "when dependency is a Python package" do
      let(:dependency_name) { "numpy" }

      before do
        python_metadata_finder = instance_double(Dependabot::Python::MetadataFinder)
        allow(Dependabot::Python::MetadataFinder).to receive(:new).and_return(python_metadata_finder)
        allow(python_metadata_finder).to receive(:look_up_source).and_return(
          Dependabot::Source.new(provider: "github", repo: "numpy/numpy")
        )
        allow(python_metadata_finder).to receive(:homepage_url).and_return("https://numpy.org")
      end

      it "delegates to Python metadata finder and returns source URL" do
        expect(metadata_finder.source_url).to eq("https://github.com/numpy/numpy")
      end
    end

    context "when dependency is not a Python package" do
      let(:dependency_name) { "git" }

      it "returns nil for non-Python packages" do
        expect(metadata_finder.source_url).to be_nil
      end
    end

    context "when dependency is cmake (non-Python package)" do
      let(:dependency_name) { "cmake" }

      it "returns nil for cmake" do
        expect(metadata_finder.source_url).to be_nil
      end
    end

    context "when dependency is requests (Python package)" do
      let(:dependency_name) { "requests" }

      before do
        python_metadata_finder = instance_double(Dependabot::Python::MetadataFinder)
        allow(Dependabot::Python::MetadataFinder).to receive(:new).and_return(python_metadata_finder)
        allow(python_metadata_finder).to receive(:look_up_source).and_return(
          Dependabot::Source.new(provider: "github", repo: "psf/requests")
        )
        allow(python_metadata_finder).to receive(:homepage_url).and_return("https://requests.readthedocs.io")
      end

      it "delegates to Python metadata finder and returns source URL" do
        expect(metadata_finder.source_url).to eq("https://github.com/psf/requests")
      end
    end
  end

  describe "#homepage_url" do
    context "when dependency is a Python package" do
      let(:dependency_name) { "numpy" }

      before do
        python_metadata_finder = instance_double(Dependabot::Python::MetadataFinder)
        allow(Dependabot::Python::MetadataFinder).to receive(:new).and_return(python_metadata_finder)
        allow(python_metadata_finder).to receive(:homepage_url).and_return("https://numpy.org")
      end

      it "delegates to Python metadata finder and returns homepage URL" do
        expect(metadata_finder.homepage_url).to eq("https://numpy.org")
      end
    end

    context "when dependency is not a Python package" do
      let(:dependency_name) { "git" }

      it "returns source_url from base class for non-Python packages" do
        expect(metadata_finder.homepage_url).to be_nil
      end
    end
  end

  describe "#python_package?" do
    let(:dependency_name) { "numpy" }

    it "delegates to PythonPackageClassifier" do
      allow(Dependabot::Conda::PythonPackageClassifier)
        .to receive(:python_package?)
        .with("numpy")
        .and_return(true)

      expect(metadata_finder.send(:python_package?, "numpy")).to be(true)
    end
  end
end
