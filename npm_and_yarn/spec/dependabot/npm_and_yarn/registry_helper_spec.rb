# typed: false
# frozen_string_literal: true

require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/registry_helper"
require "spec_helper"

RSpec.describe Dependabot::NpmAndYarn::RegistryHelper do
  let(:npmrc_file) do
    Dependabot::DependencyFile.new(
      name: ".npmrc",
      content: <<~NPMRC
        registry=https://custom-registry.com/
        _authToken=custom-token
      NPMRC
    )
  end

  let(:npmrc_without_token_file) do
    Dependabot::DependencyFile.new(
      name: ".npmrc",
      content: <<~NPMRC
        registry=https://custom-registry.com/
      NPMRC
    )
  end

  let(:empty_npmrc_file) do
    Dependabot::DependencyFile.new(name: ".npmrc", content: "")
  end

  let(:yarnrc_file) do
    Dependabot::DependencyFile.new(
      name: ".yarnrc",
      content: <<~YARNRC
        registry=https://yarn-registry.com/
        _authToken=yarn-token
      YARNRC
    )
  end

  let(:yarnrc_without_token_file) do
    Dependabot::DependencyFile.new(
      name: ".yarnrc",
      content: <<~YARNRC
        registry=https://yarn-registry.com/
      YARNRC
    )
  end

  let(:empty_yarnrc_file) do
    Dependabot::DependencyFile.new(name: ".yarnrc", content: "")
  end

  let(:yarnrc_yml_file) do
    Dependabot::DependencyFile.new(
      name: "yarnrc.yml",
      content: <<~YAML
        npmRegistryServer: "https://yarnrc-yml-registry.com/"
        npmAuthToken: "yarnrc-yml-token"
      YAML
    )
  end

  let(:yarnrc_yml_without_token_file) do
    Dependabot::DependencyFile.new(
      name: "yarnrc.yml",
      content: <<~YAML
        npmRegistryServer: "https://yarnrc-yml-registry.com/"
      YAML
    )
  end

  let(:empty_yarnrc_yml_file) do
    Dependabot::DependencyFile.new(name: "yarnrc.yml", content: "")
  end

  describe "#find_corepack_env_variables" do
    context "when npmrc is provided" do
      let(:registry_config_files) { { npmrc: npmrc_file } }

      it "returns registry and token from npmrc" do
        helper = described_class.new(registry_config_files, [])
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).to eq(
          "COREPACK_NPM_REGISTRY" => "https://custom-registry.com/",
          "COREPACK_NPM_TOKEN" => "custom-token"
        )
      end
    end

    context "when npmrc has registry but no token" do
      let(:registry_config_files) { { npmrc: npmrc_without_token_file } }

      it "returns only the registry from npmrc" do
        helper = described_class.new(registry_config_files, [])
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).to eq(
          "COREPACK_NPM_REGISTRY" => "https://custom-registry.com/"
        )
      end
    end

    context "when yarnrc is provided" do
      let(:registry_config_files) { { yarnrc: yarnrc_file } }

      it "returns registry and token from yarnrc" do
        helper = described_class.new(registry_config_files, [])
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).to eq(
          "COREPACK_NPM_REGISTRY" => "https://yarn-registry.com/",
          "COREPACK_NPM_TOKEN" => "yarn-token"
        )
      end
    end

    context "when yarnrc has registry but no token" do
      let(:registry_config_files) { { yarnrc: yarnrc_without_token_file } }

      it "returns only the registry from yarnrc" do
        helper = described_class.new(registry_config_files, [])
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).to eq(
          "COREPACK_NPM_REGISTRY" => "https://yarn-registry.com/"
        )
      end
    end

    context "when yarnrc.yml is provided" do
      let(:registry_config_files) { { yarnrc_yml: yarnrc_yml_file } }

      it "returns registry and token from yarnrc.yml" do
        helper = described_class.new(registry_config_files, [])
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).to eq(
          "COREPACK_NPM_REGISTRY" => "https://yarnrc-yml-registry.com/",
          "COREPACK_NPM_TOKEN" => "yarnrc-yml-token"
        )
      end
    end

    context "when yarnrc.yml has registry but no token" do
      let(:registry_config_files) { { yarnrc_yml: yarnrc_yml_without_token_file } }

      it "returns only the registry from yarnrc.yml" do
        helper = described_class.new(registry_config_files, [])
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).to eq(
          "COREPACK_NPM_REGISTRY" => "https://yarnrc-yml-registry.com/"
        )
      end
    end
  end
end
