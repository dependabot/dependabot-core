# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/conda/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Conda::MetadataFinder do
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.0.0",
      requirements: dependency_requirements,
      package_manager: "conda"
    )
  end
  let(:dependency_requirements) do
    [{
      file: "environment.yml",
      requirement: "=1.0.0",
      groups: dependency_groups,
      source: nil
    }]
  end
  let(:dependency_groups) { ["dependencies"] } # Default to conda dependency
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
    context "when dependency is from pip section" do
      let(:dependency_name) { "requests" }
      let(:dependency_groups) { ["pip"] }

      before do
        python_metadata_finder = instance_double(Dependabot::Python::MetadataFinder)
        allow(Dependabot::Python::MetadataFinder).to receive(:new).and_return(python_metadata_finder)
        allow(python_metadata_finder).to receive_messages(
          look_up_source: Dependabot::Source.new(provider: "github", repo: "psf/requests"),
          homepage_url: "https://requests.readthedocs.io"
        )
      end

      it "delegates to Python metadata finder and returns source URL" do
        expect(metadata_finder.source_url).to eq("https://github.com/psf/requests")
      end
    end

    context "when dependency is from conda section" do
      let(:dependency_name) { "numpy" }
      let(:dependency_groups) { ["dependencies"] }

      it "returns nil for conda packages (no GitHub link in Conda API)" do
        expect(metadata_finder.source_url).to be_nil
      end
    end

    context "when dependency is cmake (conda package)" do
      let(:dependency_name) { "cmake" }
      let(:dependency_groups) { ["dependencies"] }

      it "returns nil for cmake" do
        expect(metadata_finder.source_url).to be_nil
      end
    end
  end

  describe "#homepage_url" do
    context "when dependency is from pip section" do
      let(:dependency_name) { "requests" }
      let(:dependency_groups) { ["pip"] }

      before do
        python_metadata_finder = instance_double(Dependabot::Python::MetadataFinder)
        allow(Dependabot::Python::MetadataFinder).to receive(:new).and_return(python_metadata_finder)
        allow(python_metadata_finder).to receive(:homepage_url).and_return("https://requests.readthedocs.io")
      end

      it "delegates to Python metadata finder and returns homepage URL" do
        expect(metadata_finder.homepage_url).to eq("https://requests.readthedocs.io")
      end
    end

    context "when dependency is from conda section" do
      let(:dependency_name) { "numpy" }
      let(:dependency_groups) { ["dependencies"] }

      it "returns nil for conda packages (no homepage in Conda API)" do
        expect(metadata_finder.homepage_url).to be_nil
      end
    end
  end

  describe "#pip_dependency?" do
    context "when dependency has pip in groups" do
      let(:dependency_name) { "requests" }
      let(:dependency_groups) { ["pip"] }

      it "returns true" do
        expect(metadata_finder.send(:pip_dependency?)).to be(true)
      end
    end

    context "when dependency has dependencies in groups" do
      let(:dependency_name) { "numpy" }
      let(:dependency_groups) { ["dependencies"] }

      it "returns false" do
        expect(metadata_finder.send(:pip_dependency?)).to be(false)
      end
    end
  end
end
