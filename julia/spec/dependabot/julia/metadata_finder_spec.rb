# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/julia/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Julia::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.2.0",
      requirements: requirements,
      package_manager: "julia"
    )
  end
  let(:dependency_name) { "Example" }
  let(:requirements) do
    [{
      file: "Project.toml",
      requirement: "~1.2.0",
      groups: [],
      source: dependency_source
    }]
  end
  let(:dependency_source) { nil }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "when the source is specified in the dependency requirements" do
      let(:dependency_source) do
        { url: "https://github.com/JuliaLang/Example.jl" }
      end

      it "returns the source URL" do
        expect(source_url).to eq("https://github.com/JuliaLang/Example.jl")
      end
    end

    context "when package info exists in the registry" do
      before do
        registry_client = instance_double("Dependabot::Julia::RegistryClient")
        allow(Dependabot::Julia::RegistryClient).to receive(:new).and_return(registry_client)
        allow(registry_client).to receive(:fetch_package_info)
          .with("Example")
          .and_return({"repo" => "https://github.com/JuliaLang/Example.jl"})
      end

      it "returns the URL from the registry" do
        expect(source_url).to eq("https://github.com/JuliaLang/Example.jl")
      end
    end

    context "when registry client raises an error" do
      before do
        registry_client = instance_double("Dependabot::Julia::RegistryClient")
        allow(Dependabot::Julia::RegistryClient).to receive(:new).and_return(registry_client)
        allow(registry_client).to receive(:fetch_package_info)
          .with("Example")
          .and_raise(StandardError.new("Registry error"))
      end

      it "falls back to constructing URL from package name" do
        expect(source_url).to eq("https://github.com/JuliaLang/Example.jl")
      end
    end

    context "when package name doesn't end with .jl" do
      let(:dependency_name) { "Example" }

      before do
        registry_client = instance_double("Dependabot::Julia::RegistryClient")
        allow(Dependabot::Julia::RegistryClient).to receive(:new).and_return(registry_client)
        allow(registry_client).to receive(:fetch_package_info)
          .with("Example")
          .and_return({}) # No repo info
      end

      it "appends .jl to the package name in fallback URL" do
        expect(source_url).to eq("https://github.com/JuliaLang/Example.jl")
      end
    end

    context "when package name already ends with .jl" do
      let(:dependency_name) { "Example.jl" }

      before do
        registry_client = instance_double("Dependabot::Julia::RegistryClient")
        allow(Dependabot::Julia::RegistryClient).to receive(:new).and_return(registry_client)
        allow(registry_client).to receive(:fetch_package_info)
          .with("Example.jl")
          .and_return({}) # No repo info
      end

      it "uses the package name as-is in fallback URL" do
        expect(source_url).to eq("https://github.com/JuliaLang/Example.jl")
      end
    end
  end
end
