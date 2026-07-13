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

  let(:default_registry_npmrc_file) do
    Dependabot::DependencyFile.new(
      name: ".npmrc",
      content: <<~NPMRC
        registry=https://registry.npmjs.org/
        _authToken=default-token
      NPMRC
    )
  end

  let(:yarnrc_file) do
    Dependabot::DependencyFile.new(
      name: ".yarnrc",
      content: <<~YARNRC
        registry "https://yarn-registry.com/"
        "@scope:registry" "https://custom-registry.example.com/"
        "_authToken" "your-auth-token-here"
      YARNRC
    )
  end

  let(:yarnrc_without_token_file) do
    Dependabot::DependencyFile.new(
      name: ".yarnrc",
      content: <<~YARNRC
        registry "https://yarn-registry.com/"
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

  describe ".normalize_registry_url" do
    it "adds https scheme when missing" do
      expect(described_class.normalize_registry_url("my-registry.com/npm")).to eq("https://my-registry.com/npm")
    end

    it "preserves an existing https scheme" do
      expect(described_class.normalize_registry_url("https://my-registry.com/npm")).to eq("https://my-registry.com/npm")
    end

    it "strips a single trailing slash" do
      expect(described_class.normalize_registry_url("https://my-registry.com/npm/")).to eq("https://my-registry.com/npm")
    end

    it "strips multiple trailing slashes" do
      expect(described_class.normalize_registry_url("https://my-registry.com/npm///")).to eq("https://my-registry.com/npm")
    end

    it "preserves a path component while stripping the trailing slash" do
      expect(described_class.normalize_registry_url("https://host.example.com/npm/")).to eq("https://host.example.com/npm")
    end
  end

  describe "#find_corepack_env_variables" do
    let(:npm_signing_keys) do
      [{
        "expires" => nil,
        "keyid" => "SHA256:npm",
        "keytype" => "ecdsa-sha2-nistp256",
        "scheme" => "ecdsa-sha2-nistp256",
        "key" => "npm-public-key"
      }]
    end

    let(:registry_signing_keys) do
      [{
        "expires" => nil,
        "keyid" => "SHA256:registry",
        "keytype" => "ecdsa-sha2-nistp256",
        "scheme" => "ecdsa-sha2-nistp256",
        "key" => "registry-public-key"
      }]
    end

    # Reset the per-job integrity-keys cache around each example so fetches are
    # fresh and no fake keys leak into other specs in the same process.
    before { described_class.instance_variable_set(:@integrity_keys_cache, {}) }
    after { described_class.instance_variable_set(:@integrity_keys_cache, {}) }

    context "when npmrc is provided" do
      let(:registry_config_files) { { npmrc: npmrc_file } }

      it "returns registry from npmrc with trailing slash stripped" do
        helper = described_class.new(registry_config_files, [])
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).to eq(
          "COREPACK_NPM_REGISTRY" => "https://custom-registry.com",
          "npm_config_registry" => "https://custom-registry.com",
          "COREPACK_NPM_TOKEN" => "custom-token",
          "registry" => "https://custom-registry.com"
        )
      end
    end

    context "when credentials are provided with npm_registry type and replaces-base" do
      let(:registry_config_files) { {} }
      let(:credentials) do
        [
          {
            "type" => "npm_registry",
            "registry" => "artifactory.example.com/npm",
            "token" => "my-token",
            "replaces-base" => true
          }
        ]
      end

      before do
        stub_request(:get, "https://registry.npmjs.org/-/npm/v1/keys")
          .to_return(status: 200, body: JSON.generate({ "keys" => npm_signing_keys }))
        stub_request(:get, "https://artifactory.example.com/npm/-/npm/v1/keys")
          .with(headers: { "Authorization" => "Bearer my-token" })
          .to_return(status: 200, body: JSON.generate({ "keys" => registry_signing_keys }))
      end

      it "returns registry with https scheme and merged Corepack integrity keys" do
        helper = described_class.new(registry_config_files, credentials)
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).to eq(
          "COREPACK_NPM_REGISTRY" => "https://artifactory.example.com/npm",
          "npm_config_registry" => "https://artifactory.example.com/npm",
          "COREPACK_NPM_TOKEN" => "my-token",
          "registry" => "https://artifactory.example.com/npm",
          "COREPACK_INTEGRITY_KEYS" => JSON.generate("npm" => npm_signing_keys + registry_signing_keys)
        )
      end

      context "when a key endpoint fetch fails" do
        before do
          stub_request(:get, "https://artifactory.example.com/npm/-/npm/v1/keys")
            .to_return(status: 500, body: "boom")
        end

        it "leaves Corepack integrity keys unset rather than disabling verification" do
          helper = described_class.new(registry_config_files, credentials)
          env_variables = helper.find_corepack_env_variables
          expect(env_variables).not_to have_key("COREPACK_INTEGRITY_KEYS")
        end
      end
    end

    context "when credentials are provided with a trailing slash in the registry URL" do
      let(:registry_config_files) { {} }
      let(:credentials) do
        [
          {
            "type" => "npm_registry",
            "registry" => "artifactory.example.com/npm/",
            "token" => "my-token",
            "replaces-base" => true
          }
        ]
      end

      before do
        stub_request(:get, "https://registry.npmjs.org/-/npm/v1/keys")
          .to_return(status: 200, body: JSON.generate({ "keys" => npm_signing_keys }))
        stub_request(:get, "https://artifactory.example.com/npm/-/npm/v1/keys")
          .to_return(status: 200, body: JSON.generate({ "keys" => registry_signing_keys }))
      end

      it "strips the trailing slash from the registry URL" do
        helper = described_class.new(registry_config_files, credentials)
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).to eq(
          "COREPACK_NPM_REGISTRY" => "https://artifactory.example.com/npm",
          "npm_config_registry" => "https://artifactory.example.com/npm",
          "COREPACK_NPM_TOKEN" => "my-token",
          "registry" => "https://artifactory.example.com/npm",
          "COREPACK_INTEGRITY_KEYS" => JSON.generate("npm" => npm_signing_keys + registry_signing_keys)
        )
      end
    end

    context "when credentials are provided without replaces-base" do
      let(:registry_config_files) { {} }
      let(:credentials) do
        [
          {
            "type" => "npm_registry",
            "registry" => "artifactory.example.com/npm",
            "token" => "my-token",
            "replaces-base" => false
          }
        ]
      end

      it "does not set Corepack integrity keys and does not fetch keys" do
        helper = described_class.new(registry_config_files, credentials)
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).not_to have_key("COREPACK_INTEGRITY_KEYS")
        expect(WebMock).not_to have_requested(:get, "https://registry.npmjs.org/-/npm/v1/keys")
      end
    end

    context "when no private registry is configured" do
      let(:registry_config_files) { {} }

      it "does not set Corepack integrity keys" do
        helper = described_class.new(registry_config_files, [])
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).not_to have_key("COREPACK_INTEGRITY_KEYS")
      end
    end

    context "when npmrc has registry but no token" do
      let(:registry_config_files) { { npmrc: npmrc_without_token_file } }

      it "returns only the registry from npmrc with trailing slash stripped" do
        helper = described_class.new(registry_config_files, [])
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).to eq(
          "COREPACK_NPM_REGISTRY" => "https://custom-registry.com",
          "npm_config_registry" => "https://custom-registry.com",
          "registry" => "https://custom-registry.com"
        )
      end
    end

    context "when npmrc points to the default npm registry" do
      let(:registry_config_files) { { npmrc: default_registry_npmrc_file } }

      it "does not disable corepack integrity verification" do
        helper = described_class.new(registry_config_files, [])
        env_variables = helper.find_corepack_env_variables

        expect(env_variables).to eq(
          "COREPACK_NPM_TOKEN" => "default-token"
        )
      end
    end

    context "when yarnrc is provided" do
      let(:registry_config_files) { { yarnrc: yarnrc_file } }

      it "returns registry from yarnrc with trailing slash stripped" do
        helper = described_class.new(registry_config_files, [])
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).to eq(
          "COREPACK_NPM_REGISTRY" => "https://yarn-registry.com",
          "npm_config_registry" => "https://yarn-registry.com",
          "COREPACK_NPM_TOKEN" => "your-auth-token-here",
          "registry" => "https://yarn-registry.com"
        )
      end
    end

    context "when yarnrc has registry but no token" do
      let(:registry_config_files) { { yarnrc: yarnrc_without_token_file } }

      it "returns only the registry from yarnrc with trailing slash stripped" do
        helper = described_class.new(registry_config_files, [])
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).to eq(
          "COREPACK_NPM_REGISTRY" => "https://yarn-registry.com",
          "npm_config_registry" => "https://yarn-registry.com",
          "registry" => "https://yarn-registry.com"
        )
      end
    end

    context "when yarnrc.yml is provided" do
      let(:registry_config_files) { { yarnrc_yml: yarnrc_yml_file } }

      it "returns registry from yarnrc.yml with trailing slash stripped" do
        helper = described_class.new(registry_config_files, [])
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).to eq(
          "COREPACK_NPM_REGISTRY" => "https://yarnrc-yml-registry.com",
          "npm_config_registry" => "https://yarnrc-yml-registry.com",
          "COREPACK_NPM_TOKEN" => "yarnrc-yml-token",
          "registry" => "https://yarnrc-yml-registry.com"
        )
      end
    end

    context "when yarnrc.yml has registry but no token" do
      let(:registry_config_files) { { yarnrc_yml: yarnrc_yml_without_token_file } }

      it "returns only the registry from yarnrc.yml with trailing slash stripped" do
        helper = described_class.new(registry_config_files, [])
        env_variables = helper.find_corepack_env_variables
        expect(env_variables).to eq(
          "COREPACK_NPM_REGISTRY" => "https://yarnrc-yml-registry.com",
          "npm_config_registry" => "https://yarnrc-yml-registry.com",
          "registry" => "https://yarnrc-yml-registry.com"
        )
      end
    end
  end
end
