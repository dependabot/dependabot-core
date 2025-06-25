# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/vcpkg/metadata_finder"

RSpec.describe Dependabot::Vcpkg::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: [])
  end

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.0.0",
      requirements: requirements,
      package_manager: "vcpkg"
    )
  end

  describe "#source_url" do
    context "when the dependency is the main VCPKG baseline" do
      let(:dependency_name) { "github.com/microsoft/vcpkg" }
      let(:requirements) do
        [{
          requirement: nil,
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/microsoft/vcpkg.git",
            ref: "master"
          },
          file: "vcpkg.json"
        }]
      end

      it "returns the VCPKG repository URL" do
        expect(finder.source_url).to eq("https://github.com/microsoft/vcpkg")
      end
    end

    context "when the dependency is an individual package" do
      let(:dependency_name) { "fmt" }
      let(:requirements) { [] }

      it "returns the VCPKG repository URL" do
        expect(finder.source_url).to eq("https://github.com/microsoft/vcpkg")
      end
    end

    context "with a custom package source" do
      let(:dependency_name) { "custom-package" }
      let(:requirements) do
        [{
          requirement: nil,
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/example/custom-package.git",
            ref: "main"
          },
          file: "vcpkg.json"
        }]
      end

      it "returns the custom repository URL" do
        expect(finder.source_url).to eq("https://github.com/example/custom-package")
      end
    end
  end

  describe "#homepage_url" do
    context "when the dependency is the main VCPKG baseline" do
      let(:dependency_name) { "github.com/microsoft/vcpkg" }
      let(:requirements) do
        [{
          requirement: nil,
          groups: [],
          source: {
            type: "git",
            url: "https://github.com/microsoft/vcpkg.git",
            ref: "master"
          },
          file: "vcpkg.json"
        }]
      end

      it "returns the VCPKG homepage" do
        expect(finder.homepage_url).to eq("https://vcpkg.io")
      end
    end

    context "when the dependency is an individual package" do
      let(:dependency_name) { "fmt" }
      let(:requirements) { [] }

      it "returns the package page on VCPKG" do
        expect(finder.homepage_url).to eq("https://vcpkg.io/en/package/fmt")
      end
    end
  end
end
