# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "json"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/terraform/file_updater/provider_cli_config_builder"

RSpec.describe Dependabot::Terraform::FileUpdater::ProviderCliConfigBuilder do
  extend T::Sig

  # Builds a JSON string matching the hcl2json output format for a
  # terraform required_providers block.
  sig { params(providers: T::Hash[String, Object]).returns(String) }
  def providers_json(providers)
    JSON.generate(
      "terraform" => [{ "required_providers" => [providers] }]
    )
  end

  sig { returns(Dependabot::Terraform::FileUpdater::ProviderCliConfigBuilder) } # rubocop:disable RSpec/DescribedClass -- Concrete type.
  subject(:builder) do
    described_class.new(
      dependency: dependency,
      terraform_files: terraform_files
    )
  end

  # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
  sig { returns(Dependabot::Dependency) }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "hashicorp/aws",
      version: "3.42.0",
      previous_version: "3.37.0",
      requirements: [{
        requirement: "3.42.0",
        groups: [],
        file: "versions.tf",
        source: source
      }],
      previous_requirements: [{
        requirement: "3.37.0",
        groups: [],
        file: "versions.tf",
        source: source
      }],
      package_manager: "terraform"
    )
  end

  sig { returns(Dependabot::DependencyRequirement::Source) }
  let(:source) do
    {
      type: "provider",
      registry_hostname: "registry.terraform.io",
      module_identifier: "hashicorp/aws"
    }
  end

  sig { returns(T::Array[Dependabot::DependencyFile]) }
  let(:terraform_files) { [] }
  # rubocop:enable RSpec/ScatteredLet

  # Stub the hcl2json binary — the external boundary. parse_hcl_file writes
  # file.content to tmp.tf then runs hcl2json, so we set file content to
  # the desired JSON and echo it back via the stub.
  before do
    allow(Open3).to receive(:capture3).and_wrap_original do |original, *args|
      if args.first&.include?("hcl2json")
        content = File.exist?("tmp.tf") ? File.read("tmp.tf") : "{}"
        [content, "", instance_double(Process::Status, success?: true)]
      else
        original.call(*args)
      end
    end
  end

  describe "#env" do
    context "when the dependency is a git source (not a provider)" do
      sig { returns(Dependabot::Dependency) }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "origin_label",
          version: "0.4.1",
          previous_version: "0.3.7",
          requirements: [{
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-null-label.git",
              ref: "tags/0.4.1"
            }
          }],
          previous_requirements: [{
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-null-label.git",
              ref: "tags/0.3.7"
            }
          }],
          package_manager: "terraform"
        )
      end

      it "returns an empty hash" do
        expect(builder.env).to eq({})
      end
    end

    context "when no terraform files are provided" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:terraform_files) { [] }

      it "returns an empty hash" do
        expect(builder.env).to eq({})
      end
    end

    context "when the only provider in the file is the target provider" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:terraform_files) do
        [
          Dependabot::DependencyFile.new(
            name: "versions.tf",
            content: providers_json(
              "aws" => { "source" => "hashicorp/aws", "version" => ">= 3.37.0" }
            )
          )
        ]
      end

      it "returns an empty hash" do
        expect(builder.env).to eq({})
      end
    end

    context "when there are non-target providers" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:terraform_files) do
        [
          Dependabot::DependencyFile.new(
            name: "versions.tf",
            content: providers_json(
              "aws" => { "source" => "hashicorp/aws", "version" => ">= 3.37.0" },
              "nonexistent" => { "source" => "acme-corp/nonexistent", "version" => ">= 0.1" }
            )
          )
        ]
      end

      after { builder.cleanup }

      it "returns a TF_CLI_CONFIG_FILE env var" do
        result = builder.env
        expect(result).to have_key("TF_CLI_CONFIG_FILE")
        expect(File.exist?(result["TF_CLI_CONFIG_FILE"])).to be true
      end

      it "generates config with dev_overrides for the non-target provider only" do
        config_path = builder.env.fetch("TF_CLI_CONFIG_FILE")
        config_content = File.read(config_path)

        expect(config_content).to include("registry.terraform.io/acme-corp/nonexistent")
        expect(config_content).not_to include("hashicorp/aws")
      end

      it "generates valid terraform CLI config structure" do
        config_path = builder.env.fetch("TF_CLI_CONFIG_FILE")
        config_content = File.read(config_path)

        expect(config_content).to include("provider_installation {")
        expect(config_content).to include("dev_overrides {")
        expect(config_content).to include("direct {}")
      end

      context "when the target requirement source uses string keys" do
        sig { returns(Dependabot::DependencyRequirement::Source) }
        let(:source) do
          {
            "type" => "provider",
            "registry_hostname" => "registry.terraform.io",
            "module_identifier" => "hashicorp/aws"
          }
        end

        it "still excludes the target provider" do
          config_content = File.read(builder.env.fetch("TF_CLI_CONFIG_FILE"))

          expect(config_content).to include("registry.terraform.io/acme-corp/nonexistent")
          expect(config_content).not_to include("hashicorp/aws")
        end
      end
    end

    context "when providers span multiple files" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:terraform_files) do
        [
          Dependabot::DependencyFile.new(
            name: "versions.tf",
            content: providers_json(
              "aws" => { "source" => "hashicorp/aws", "version" => ">= 3.37.0" }
            )
          ),
          Dependabot::DependencyFile.new(
            name: "modules/providers.tf",
            content: providers_json(
              "azurerm" => { "source" => "hashicorp/azurerm", "version" => ">= 2.48.0" }
            )
          )
        ]
      end

      after { builder.cleanup }

      it "collects providers from all files" do
        config_path = builder.env.fetch("TF_CLI_CONFIG_FILE")
        config_content = File.read(config_path)

        expect(config_content).to include("registry.terraform.io/hashicorp/azurerm")
        expect(config_content).not_to include("hashicorp/aws")
      end
    end

    context "with a provider using a two-part source address" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:terraform_files) do
        [
          Dependabot::DependencyFile.new(
            name: "versions.tf",
            content: providers_json(
              "aws" => { "source" => "hashicorp/aws", "version" => ">= 3.0" },
              "datadog" => { "source" => "DataDog/datadog", "version" => ">= 3.0" }
            )
          )
        ]
      end

      after { builder.cleanup }

      it "prepends the default registry hostname" do
        config_content = File.read(builder.env.fetch("TF_CLI_CONFIG_FILE"))

        expect(config_content).to include("registry.terraform.io/datadog/datadog")
      end
    end

    context "with a provider using a three-part source address (custom registry)" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:terraform_files) do
        [
          Dependabot::DependencyFile.new(
            name: "versions.tf",
            content: providers_json(
              "aws" => { "source" => "hashicorp/aws", "version" => ">= 3.0" },
              "custom" => { "source" => "custom.registry.io/org/custom", "version" => ">= 1.0" }
            )
          )
        ]
      end

      after { builder.cleanup }

      it "uses the source address as-is" do
        config_content = File.read(builder.env.fetch("TF_CLI_CONFIG_FILE"))

        expect(config_content).to include("custom.registry.io/org/custom")
      end
    end

    context "with a provider that has no explicit source" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:terraform_files) do
        [
          Dependabot::DependencyFile.new(
            name: "versions.tf",
            content: providers_json(
              "aws" => { "source" => "hashicorp/aws", "version" => ">= 3.0" },
              "random" => { "version" => ">= 3.0" }
            )
          )
        ]
      end

      after { builder.cleanup }

      it "defaults to registry.terraform.io/hashicorp/<name>" do
        config_content = File.read(builder.env.fetch("TF_CLI_CONFIG_FILE"))

        expect(config_content).to include("registry.terraform.io/hashicorp/random")
      end
    end

    context "with mixed-case provider source addresses" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:terraform_files) do
        [
          Dependabot::DependencyFile.new(
            name: "versions.tf",
            content: providers_json(
              "aws" => { "source" => "hashicorp/aws", "version" => ">= 3.0" },
              "dd" => { "source" => "DataDog/Datadog", "version" => ">= 3.0" }
            )
          )
        ]
      end

      after { builder.cleanup }

      it "normalizes source addresses to lowercase" do
        config_content = File.read(builder.env.fetch("TF_CLI_CONFIG_FILE"))

        expect(config_content).to include("registry.terraform.io/datadog/datadog")
        expect(config_content).not_to include("DataDog")
      end
    end

    context "when the same provider appears in multiple files" do
      # rubocop:disable RSpec/ScatteredLet -- Grouping lets would detach their required Sorbet signatures.
      sig { returns(String) }
      let(:provider_json) do
        providers_json(
          "aws" => { "source" => "hashicorp/aws", "version" => ">= 3.0" },
          "random" => { "source" => "hashicorp/random", "version" => ">= 3.0" }
        )
      end

      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:terraform_files) do
        [
          Dependabot::DependencyFile.new(name: "a.tf", content: provider_json),
          Dependabot::DependencyFile.new(name: "b.tf", content: provider_json)
        ]
      end
      # rubocop:enable RSpec/ScatteredLet

      after { builder.cleanup }

      it "deduplicates provider sources" do
        config_content = File.read(builder.env.fetch("TF_CLI_CONFIG_FILE"))

        occurrences = config_content.scan("registry.terraform.io/hashicorp/random").length
        expect(occurrences).to eq(1)
      end
    end

    context "when a provider entry is a string rather than a hash" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:terraform_files) do
        [
          Dependabot::DependencyFile.new(
            name: "versions.tf",
            content: providers_json(
              "aws" => { "source" => "hashicorp/aws", "version" => ">= 3.0" },
              "random" => "hashicorp/random"
            )
          )
        ]
      end

      it "skips non-hash provider entries without error" do
        expect { builder.env }.not_to raise_error
      end
    end

    context "when the hcl2json parser returns empty output" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:terraform_files) do
        [Dependabot::DependencyFile.new(name: "bad.tf", content: "{}")]
      end

      it "returns an empty hash" do
        expect(builder.env).to eq({})
      end
    end
  end

  describe "#cleanup" do
    context "when env has not been called" do
      it "does not raise" do
        expect { builder.cleanup }.not_to raise_error
      end
    end

    context "when env has been called and created temp files" do
      sig { returns(T::Array[Dependabot::DependencyFile]) }
      let(:terraform_files) do
        [
          Dependabot::DependencyFile.new(
            name: "versions.tf",
            content: providers_json(
              "aws" => { "source" => "hashicorp/aws", "version" => ">= 3.0" },
              "private" => { "source" => "acme/private", "version" => ">= 1.0" }
            )
          )
        ]
      end

      it "removes the config file and dev_override directory" do
        config_path = builder.env.fetch("TF_CLI_CONFIG_FILE")

        config_content = File.read(config_path)
        match = T.must(config_content.match(/"([^"]*dependabot-tf-dev[^"]*)"/))
        dev_dir = T.must(match[1])

        expect(File.exist?(config_path)).to be true
        expect(Dir.exist?(dev_dir)).to be true

        builder.cleanup

        expect(File.exist?(config_path)).to be false
        expect(Dir.exist?(dev_dir)).to be false
      end

      it "is safe to call multiple times" do
        builder.env

        builder.cleanup
        expect { builder.cleanup }.not_to raise_error
      end
    end
  end
end
