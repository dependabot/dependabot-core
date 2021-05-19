# frozen_string_literal: true

require "spec_helper"
require "dependabot/terraform/registry_client"

RSpec.describe Dependabot::Terraform::RegistryClient do
  let(:module_dependency) do
    Dependabot::Dependency.new(
      name: "hashicorp/consul/aws",
      version: "0.9.3",
      package_manager: "terraform",
      previous_version: "0.1.0",
      requirements: [{
        requirement: "0.3.8",
        groups: [],
        file: "main.tf",
        source: {
          type: "registry",
          registry_hostname: "registry.terraform.io",
          module_identifier: "hashicorp/consul/aws"
        }
      }],
      previous_requirements: [{
        requirement: "0.1.0",
        groups: [],
        file: "main.tf",
        source: {
          type: "registry",
          registry_hostname: "registry.terraform.io",
          module_identifier: "hashicorp/consul/aws"
        }
      }]
    )
  end

  it "fetches module versions", :vcr do
    client = described_class.new(hostname: described_class::PUBLIC_HOSTNAME)
    response = client.all_module_versions(identifier: "hashicorp/consul/aws")
    expect(response.max).to eq(Gem::Version.new("0.9.3"))
  end

  it "raises an error when it cannot find the dependency", :vcr do
    client = described_class.new(hostname: described_class::PUBLIC_HOSTNAME)
    expect { client.all_module_versions(identifier: "does/not/exist") }.to raise_error(RuntimeError) do |error|
      expect(error.message).to eq("Response from registry was 404")
    end
  end

  it "does not (yet) handle custom registries" do
    client = described_class.new(hostname: "my.private-registry.io")
    response = client.all_module_versions(identifier: "hashicorp/consul/aws")
    expect(response).to eq([])
  end

  it "fetches the source for a module dependency", :vcr do
    client = described_class.new(hostname: described_class::PUBLIC_HOSTNAME)
    source = client.source(dependency: module_dependency)

    expect(source).to be_a Dependabot::Source
    expect(source.url).to eq("https://github.com/hashicorp/terraform-aws-consul")
  end
end
