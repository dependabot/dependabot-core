# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/cargo/helpers"

RSpec.describe Dependabot::Cargo::Helpers do
  describe ".sanitize_cargo_config" do
    context "when config has no credential-provider settings" do
      let(:config_content) do
        <<~TOML
          [registries.my-registry]
          index = "sparse+https://example.com/index/"
          token = "some-token"
        TOML
      end

      it "returns equivalent config with non-credential-provider keys preserved" do
        result = described_class.sanitize_cargo_config(config_content)
        parsed = TomlRB.parse(result)
        expect(parsed["registries"]["my-registry"]["index"]).to eq("sparse+https://example.com/index/")
        expect(parsed["registries"]["my-registry"]["token"]).to eq("some-token")
      end
    end

    context "when config has no registries section" do
      let(:config_content) do
        <<~TOML
          [source.crates-io]
          replace-with = "my-mirror"

          [net]
          git-fetch-with-cli = true
        TOML
      end

      it "returns equivalent config unchanged" do
        result = described_class.sanitize_cargo_config(config_content)
        parsed = TomlRB.parse(result)
        expect(parsed["source"]["crates-io"]["replace-with"]).to eq("my-mirror")
        expect(parsed["net"]["git-fetch-with-cli"]).to be true
      end
    end

    context "when config has per-registry credential-provider" do
      let(:config_content) do
        <<~TOML
          [registries.artifactory]
          index = "sparse+https://example.com/api/cargo/cargo-local/index/"
          credential-provider = "cargo:token"

          [registries.artifactory-remote]
          index = "sparse+https://example.com/api/cargo/cargo-crates-remote/index/"
          credential-provider = "cargo:token"
        TOML
      end

      it "strips credential-provider from all registries" do
        result = described_class.sanitize_cargo_config(config_content)
        parsed = TomlRB.parse(result)

        expect(parsed["registries"]["artifactory"]).not_to have_key("credential-provider")
        expect(parsed["registries"]["artifactory-remote"]).not_to have_key("credential-provider")
      end

      it "preserves index URLs" do
        result = described_class.sanitize_cargo_config(config_content)
        parsed = TomlRB.parse(result)

        expect(parsed["registries"]["artifactory"]["index"])
          .to eq("sparse+https://example.com/api/cargo/cargo-local/index/")
        expect(parsed["registries"]["artifactory-remote"]["index"])
          .to eq("sparse+https://example.com/api/cargo/cargo-crates-remote/index/")
      end
    end

    context "when config has [registry] credential-provider (e.g. for cargo publish)" do
      let(:config_content) do
        <<~TOML
          [registry]
          credential-provider = "cargo:token"
        TOML
      end

      it "strips the credential-provider" do
        result = described_class.sanitize_cargo_config(config_content)
        parsed = TomlRB.parse(result)

        expect(parsed.fetch("registry", {})).not_to have_key("credential-provider")
      end
    end

    context "when config has mixed settings" do
      let(:config_content) do
        <<~TOML
          [registries.with-cred]
          index = "sparse+https://example.com/index/"
          credential-provider = "cargo:token"

          [registries.without-cred]
          index = "sparse+https://other.example.com/index/"

          [source.crates-io]
          replace-with = "with-cred"

          [net]
          git-fetch-with-cli = true
        TOML
      end

      it "strips only credential-provider, preserves everything else" do
        result = described_class.sanitize_cargo_config(config_content)
        parsed = TomlRB.parse(result)

        expect(parsed["registries"]["with-cred"]).not_to have_key("credential-provider")
        expect(parsed["registries"]["with-cred"]["index"]).to eq("sparse+https://example.com/index/")
        expect(parsed["registries"]["without-cred"]["index"]).to eq("sparse+https://other.example.com/index/")
        expect(parsed["source"]["crates-io"]["replace-with"]).to eq("with-cred")
        expect(parsed["net"]["git-fetch-with-cli"]).to be true
      end
    end

    context "when config is malformed TOML" do
      let(:config_content) { "this is not valid toml {{{{" }

      it "raises DependencyFileNotParseable" do
        expect { described_class.sanitize_cargo_config(config_content) }
          .to raise_error(Dependabot::DependencyFileNotParseable, /Failed to parse Cargo config file/)
      end
    end
  end

  describe ".custom_registry_names" do
    it "returns empty array when no registries are defined" do
      config_content = <<~TOML
        [net]
        git-fetch-with-cli = true
      TOML
      expect(described_class.custom_registry_names(config_content, [])).to eq([])
    end

    it "returns a single registry name when credential host matches" do
      config_content = <<~TOML
        [registries.my-registry]
        index = "sparse+https://example.com/index/"
      TOML
      creds = [Dependabot::Credential.new({ "host" => "example.com" })]
      expect(described_class.custom_registry_names(config_content, creds)).to eq(["my-registry"])
    end

    it "returns only registries whose index host matches a credential host" do
      config_content = <<~TOML
        [registries.first-registry]
        index = "sparse+https://first.example.com/index/"

        [registries.second-registry]
        index = "sparse+https://second.example.com/index/"
      TOML
      creds = [Dependabot::Credential.new({ "host" => "first.example.com" })]
      expect(described_class.custom_registry_names(config_content, creds)).to eq(["first-registry"])
    end

    it "returns multiple registries when multiple credential hosts match" do
      config_content = <<~TOML
        [registries.first-registry]
        index = "sparse+https://first.example.com/index/"

        [registries.second-registry]
        index = "sparse+https://second.example.com/index/"
      TOML
      creds = [
        Dependabot::Credential.new({ "host" => "first.example.com" }),
        Dependabot::Credential.new({ "host" => "second.example.com" })
      ]
      expect(described_class.custom_registry_names(config_content, creds)).to eq(%w(first-registry second-registry))
    end

    it "ignores non-registry sections" do
      config_content = <<~TOML
        [registry]
        default = "my-registry"

        [registries.my-registry]
        index = "sparse+https://example.com/index/"

        [net]
        git-fetch-with-cli = true
      TOML
      creds = [Dependabot::Credential.new({ "host" => "example.com" })]
      expect(described_class.custom_registry_names(config_content, creds)).to eq(["my-registry"])
    end

    it "handles leading whitespace on registry lines" do
      config_content = "  [registries.spaced-registry]\n  index = \"https://example.com\"\n"
      creds = [Dependabot::Credential.new({ "host" => "example.com" })]
      expect(described_class.custom_registry_names(config_content, creds)).to eq(["spaced-registry"])
    end

    it "returns empty array for empty content" do
      expect(described_class.custom_registry_names("", [])).to eq([])
    end

    it "returns empty array when no credential hosts match" do
      config_content = <<~TOML
        [registries.my-registry]
        index = "sparse+https://example.com/index/"
      TOML
      creds = [Dependabot::Credential.new({ "host" => "other.com" })]
      expect(described_class.custom_registry_names(config_content, creds)).to eq([])
    end

    it "matches a registry when credential url matches the index URL" do
      config_content = <<~TOML
        [registries.my-registry]
        index = "sparse+https://example.com/index/"
      TOML
      creds = [Dependabot::Credential.new({ "url" => "https://example.com/index/" })]
      expect(described_class.custom_registry_names(config_content, creds)).to eq(["my-registry"])
    end

    it "matches a registry when credential url matches ignoring trailing slashes" do
      config_content = <<~TOML
        [registries.my-registry]
        index = "sparse+https://example.com/index"
      TOML
      creds = [Dependabot::Credential.new({ "url" => "https://example.com/index/" })]
      expect(described_class.custom_registry_names(config_content, creds)).to eq(["my-registry"])
    end

    it "does not match when credential url differs from index URL" do
      config_content = <<~TOML
        [registries.my-registry]
        index = "sparse+https://example.com/index/"
      TOML
      creds = [Dependabot::Credential.new({ "url" => "https://other.com/index/" })]
      expect(described_class.custom_registry_names(config_content, creds)).to eq([])
    end

    it "matches when either host or url credential matches" do
      config_content = <<~TOML
        [registries.host-registry]
        index = "sparse+https://host.example.com/index/"

        [registries.url-registry]
        index = "sparse+https://url.example.com/path/"
      TOML
      creds = [
        Dependabot::Credential.new({ "host" => "host.example.com" }),
        Dependabot::Credential.new({ "url" => "https://url.example.com/path/" })
      ]
      expect(described_class.custom_registry_names(config_content, creds)).to eq(%w(host-registry url-registry))
    end

    it "returns empty array for malformed TOML" do
      expect(described_class.custom_registry_names("not valid toml {{{{", [])).to eq([])
    end

    it "returns empty array for invalid URI in index" do
      config_content = <<~TOML
        [registries.bad]
        index = "sparse+ht tp://bad url"
      TOML
      creds = [Dependabot::Credential.new({ "host" => "bad" })]
      expect(described_class.custom_registry_names(config_content, creds)).to eq([])
    end
  end

  describe ".registry_token_env" do
    let(:config_content) do
      <<~TOML
        [registries.my-private-registry]
        index = "sparse+https://private.example.com/index/"

        [registries.another-registry]
        index = "sparse+https://another.example.com/index/"
      TOML
    end

    let(:creds) do
      [
        { "host" => "private.example.com" },
        { "host" => "another.example.com" }
      ]
    end

    it "returns token env vars for matched registries" do
      env = described_class.registry_token_env(config_content, creds)
      expect(env).to eq(
        "CARGO_REGISTRIES_MY_PRIVATE_REGISTRY_TOKEN" => "garbage_token",
        "CARGO_REGISTRIES_ANOTHER_REGISTRY_TOKEN" => "garbage_token"
      )
    end

    it "returns empty hash when no registries match" do
      env = described_class.registry_token_env(config_content, [])
      expect(env).to eq({})
    end

    it "returns empty hash for empty config" do
      env = described_class.registry_token_env("", creds)
      expect(env).to eq({})
    end
  end

  describe ".cargo_command_env" do
    let(:config_content) do
      <<~TOML
        [registries.my-registry]
        index = "sparse+https://private.example.com/index/"
      TOML
    end
    let(:creds) { [Dependabot::Credential.new({ "host" => "private.example.com" })] }
    let(:dependency_files) do
      [
        Dependabot::DependencyFile.new(name: ".cargo/config.toml", content: config_content)
      ]
    end

    before do
      ENV["DEPENDABOT"] = "true"
      Dependabot::Experiments.register(:cargo_set_registry_token_auth, true)
    end

    after do
      ENV.delete("DEPENDABOT")
      ENV.delete("CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS")
      Dependabot::Experiments.reset!
    end

    it "includes token env vars for matched registries" do
      env = described_class.cargo_command_env(dependency_files, creds)
      expect(env["CARGO_REGISTRIES_MY_REGISTRY_TOKEN"]).to eq("garbage_token")
    end

    it "always sets CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS" do
      env = described_class.cargo_command_env(dependency_files, creds)
      expect(env["CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS"]).to eq("cargo:token")
    end

    it "passes through real CARGO_REGISTRIES_* env vars" do
      allow(ENV).to receive(:select).and_return({ "CARGO_REGISTRIES_CRATES_IO_PROTOCOL" => "sparse" })
      env = described_class.cargo_command_env(dependency_files, creds)
      expect(env["CARGO_REGISTRIES_CRATES_IO_PROTOCOL"]).to eq("sparse")
    end

    it "real env vars override token env vars with same key" do
      allow(ENV).to receive(:select).and_return(
        { "CARGO_REGISTRIES_MY_REGISTRY_TOKEN" => "real_token" }
      )
      env = described_class.cargo_command_env(dependency_files, creds)
      expect(env["CARGO_REGISTRIES_MY_REGISTRY_TOKEN"]).to eq("real_token")
    end

    it "sets CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS even without config file" do
      empty_files = [Dependabot::DependencyFile.new(name: "Cargo.toml", content: "")]
      env = described_class.cargo_command_env(empty_files, creds)
      expect(env["CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS"]).to eq("cargo:token")
    end

    context "when DEPENDABOT env var is not set" do
      before { ENV.delete("DEPENDABOT") }

      it "returns empty hash" do
        env = described_class.cargo_command_env(dependency_files, creds)
        expect(env).to eq({})
      end

      it "sets CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS in ENV via ||=" do
        ENV.delete("CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS")
        described_class.cargo_command_env(dependency_files, creds)
        expect(ENV.fetch("CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS", nil)).to eq("")
      end
    end

    context "when cargo_set_registry_token_auth experiment is disabled" do
      before { Dependabot::Experiments.register(:cargo_set_registry_token_auth, false) }

      it "returns empty hash" do
        env = described_class.cargo_command_env(dependency_files, creds)
        expect(env).to eq({})
      end

      it "does not overwrite existing CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS" do
        ENV["CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS"] = "existing"
        described_class.cargo_command_env(dependency_files, creds)
        expect(ENV.fetch("CARGO_REGISTRY_GLOBAL_CREDENTIAL_PROVIDERS", nil)).to eq("existing")
      end
    end
  end
end
