# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/terraform/private_registry_logger"

RSpec.describe Dependabot::Terraform::PrivateRegistryLogger do
  describe ".private_registry?" do
    it "returns false for public registry" do
      expect(described_class.private_registry?("registry.terraform.io")).to be false
    end

    it "returns true for private registry" do
      expect(described_class.private_registry?("private-registry.example.com")).to be true
    end
  end

  describe ".log_registry_operation" do
    let(:logger) { instance_double("Logger") }

    before do
      allow(Dependabot).to receive(:logger).and_return(logger)
    end

    context "with private registry" do
      it "logs the operation" do
        expect(logger).to receive(:info).with(
          "Private registry operation: source_resolution for private-registry.example.com (module_identifier: company/vpc/aws)"
        )

        described_class.log_registry_operation(
          hostname: "private-registry.example.com",
          operation: "source_resolution",
          details: { module_identifier: "company/vpc/aws" }
        )
      end
    end

    context "with public registry" do
      it "does not log the operation" do
        expect(logger).not_to receive(:info)

        described_class.log_registry_operation(
          hostname: "registry.terraform.io",
          operation: "source_resolution",
          details: { module_identifier: "hashicorp/consul/aws" }
        )
      end
    end
  end

  describe ".log_registry_error" do
    let(:logger) { instance_double("Logger") }
    let(:error) { StandardError.new("Connection failed") }

    before do
      allow(Dependabot).to receive(:logger).and_return(logger)
    end

    context "with private registry" do
      it "logs the error" do
        expect(logger).to receive(:warn).with(
          "Private registry error: StandardError for private-registry.example.com: Connection failed (context: source_resolution)"
        )

        described_class.log_registry_error(
          hostname: "private-registry.example.com",
          error: error,
          context: { context: "source_resolution" }
        )
      end
    end

    context "with public registry" do
      it "does not log the error" do
        expect(logger).not_to receive(:warn)

        described_class.log_registry_error(
          hostname: "registry.terraform.io",
          error: error,
          context: { context: "source_resolution" }
        )
      end
    end
  end
end
