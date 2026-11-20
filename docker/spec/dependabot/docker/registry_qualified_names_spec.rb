# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/docker"
require "dependabot/docker_compose"
require "dependabot/dependency_group"
require "dependabot/config/update_config"

RSpec.describe Dependabot::Docker::RegistryQualifiedNames do
  let(:package_manager) { "docker" }
  let(:source) { { registry: "mcr.microsoft.com", tag: "10.0.401-noble" } }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "dotnet/sdk",
      version: "10.0.401-noble",
      package_manager: package_manager,
      requirements: [{ requirement: nil, groups: [], file: "Dockerfile", source: source }]
    )
  end

  describe ".for" do
    it "returns the registry-qualified image name" do
      expect(described_class.for(dependency)).to eq(["mcr.microsoft.com/dotnet/sdk"])
    end

    context "when the image has no registry" do
      let(:source) { { tag: "10.0.401-noble" } }

      it "returns no aliases" do
        expect(described_class.for(dependency)).to eq([])
      end
    end

    context "when the source uses string keys" do
      let(:source) { { "registry" => "mcr.microsoft.com", "tag" => "10.0.401-noble" } }

      it "returns the registry-qualified image name" do
        expect(described_class.for(dependency)).to eq(["mcr.microsoft.com/dotnet/sdk"])
      end
    end
  end

  %w(docker docker_compose).each do |pm|
    context "with the #{pm} package manager" do
      let(:package_manager) { pm }

      it "includes the registry-qualified name for matching" do
        expect(dependency.names_for_matching).to eq(["dotnet/sdk", "mcr.microsoft.com/dotnet/sdk"])
      end

      it "lets group patterns include the registry host" do
        group = Dependabot::DependencyGroup.new(name: "dotnet", rules: { "patterns" => ["mcr.microsoft.com/dotnet/*"] })

        expect(group.contains?(dependency)).to be(true)
      end

      it "still matches group patterns without the registry host" do
        group = Dependabot::DependencyGroup.new(name: "dotnet", rules: { "patterns" => ["dotnet/*"] })

        expect(group.contains?(dependency)).to be(true)
      end

      it "lets ignore conditions include the registry host" do
        config = Dependabot::Config::UpdateConfig.new(
          ignore_conditions: [
            Dependabot::Config::IgnoreCondition.new(dependency_name: "mcr.microsoft.com/dotnet/*", versions: [">= 0"])
          ]
        )

        expect(config.ignored_versions_for(dependency)).to eq([">= 0"])
      end
    end
  end
end
