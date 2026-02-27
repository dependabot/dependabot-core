# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/azure_devops_path_normalizer"

RSpec.describe Dependabot::GoModules::AzureDevopsPathNormalizer do
  describe ".normalize" do
    it "adds _git when missing" do
      name = "dev.azure.com/VaronisIO/da-cloud/be-protobuf.git"

      expect(described_class.normalize(name))
        .to eq("dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf.git")
    end

    it "preserves repository subdirectory paths" do
      name = "dev.azure.com/VaronisIO/da-cloud/be-protobuf.git/submodule"

      expect(described_class.normalize(name))
        .to eq("dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf.git/submodule")
    end

    it "does not modify names that already include _git" do
      name = "dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf.git"

      expect(described_class.normalize(name)).to eq(name)
    end

    it "does not modify non-Azure names" do
      name = "github.com/dependabot/dependabot-core"

      expect(described_class.normalize(name)).to eq(name)
    end
  end
end
