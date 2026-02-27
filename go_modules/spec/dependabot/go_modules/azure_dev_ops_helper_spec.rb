# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/azure_dev_ops_helper"

RSpec.describe Dependabot::GoModules::AzureDevOpsHelper do
  let(:tmp) { Dir.mktmpdir }
  let(:git_config_path) { File.expand_path("test_azure_devops.gitconfig", tmp) }

  before do
    FileUtils.mkdir_p(tmp)
    File.write(git_config_path, "")
    ENV["GIT_CONFIG_GLOBAL"] = git_config_path
  end

  after do
    ENV.delete("GIT_CONFIG_GLOBAL")
    ENV.delete("GOPRIVATE")
    FileUtils.rm_f(git_config_path)
    FileUtils.rm_rf(tmp)
  end

  describe ".configure_go_for_azure_devops" do
    context "with an Azure DevOps module path ending in .git" do
      before do
        described_class.configure_go_for_azure_devops(
          "dev.azure.com/VaronisIO/da-cloud/be-protobuf.git"
        )
      end

      it "adds git insteadOf rule for the bare URL (Go strips .git)" do
        config = `git config --global --get-all url.https://dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf.insteadOf`
        expect(config).to include("https://dev.azure.com/VaronisIO/da-cloud/be-protobuf\n")
      end

      it "adds git insteadOf rule for the .git URL" do
        config = `git config --global --get-all url.https://dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf.insteadOf`
        expect(config).to include("https://dev.azure.com/VaronisIO/da-cloud/be-protobuf.git")
      end

      it "adds git insteadOf rule for the slash URL" do
        config = `git config --global --get-all url.https://dev.azure.com/VaronisIO/da-cloud/_git/be-protobuf/.insteadOf`
        expect(config.strip).to include("https://dev.azure.com/VaronisIO/da-cloud/be-protobuf/")
      end

      it "sets GOPRIVATE" do
        expect(ENV.fetch("GOPRIVATE", nil)).to eq("dev.azure.com")
      end
    end

    context "with an Azure DevOps module path without .git" do
      before do
        described_class.configure_go_for_azure_devops(
          "dev.azure.com/MyOrg/MyProject/myrepo"
        )
      end

      it "adds git insteadOf rule for the bare URL" do
        config = `git config --global --get-all url.https://dev.azure.com/MyOrg/MyProject/_git/myrepo.insteadOf`
        expect(config).to include("https://dev.azure.com/MyOrg/MyProject/myrepo\n")
      end

      it "adds git insteadOf rule for the .git URL" do
        config = `git config --global --get-all url.https://dev.azure.com/MyOrg/MyProject/_git/myrepo.insteadOf`
        expect(config).to include("https://dev.azure.com/MyOrg/MyProject/myrepo.git")
      end

      it "adds git insteadOf rule for the slash URL" do
        config = `git config --global --get-all url.https://dev.azure.com/MyOrg/MyProject/_git/myrepo/.insteadOf`
        expect(config.strip).to include("https://dev.azure.com/MyOrg/MyProject/myrepo/")
      end

      it "sets GOPRIVATE" do
        expect(ENV.fetch("GOPRIVATE", nil)).to eq("dev.azure.com")
      end
    end

    context "with an Azure DevOps module path with subpath" do
      it "extracts the repo name correctly" do
        described_class.configure_go_for_azure_devops(
          "dev.azure.com/MyOrg/MyProject/myrepo.git/v2"
        )

        config = `git config --global --get-all url.https://dev.azure.com/MyOrg/MyProject/_git/myrepo.insteadOf`
        expect(config.strip).to include("https://dev.azure.com/MyOrg/MyProject/myrepo.git")
      end
    end

    context "with a non-Azure DevOps module path" do
      it "does not add git insteadOf rules" do
        described_class.configure_go_for_azure_devops("github.com/some/repo")

        config = `git config --global --list 2>/dev/null`
        expect(config).not_to include("insteadOf")
      end

      it "does not set GOPRIVATE" do
        described_class.configure_go_for_azure_devops("github.com/some/repo")

        expect(ENV.fetch("GOPRIVATE", nil)).to be_nil
      end
    end

    context "with an Azure DevOps path with too few segments" do
      it "does not add git insteadOf rules" do
        described_class.configure_go_for_azure_devops(
          "dev.azure.com/VaronisIO/da-cloud"
        )

        config = `git config --global --list 2>/dev/null`
        expect(config).not_to include("insteadOf")
      end
    end

    context "when called multiple times for the same module" do
      before do
        2.times do
          described_class.configure_go_for_azure_devops(
            "dev.azure.com/MyOrg/MyProject/myrepo"
          )
        end
      end

      it "does not accumulate duplicate bare URL entries" do
        config = `git config --global --get-all url.https://dev.azure.com/MyOrg/MyProject/_git/myrepo.insteadOf`
        bare_entries = config.strip.split("\n").select { |l| l.strip == "https://dev.azure.com/MyOrg/MyProject/myrepo" }
        expect(bare_entries.length).to eq(1)
      end

      it "does not accumulate duplicate .git URL entries" do
        config = `git config --global --get-all url.https://dev.azure.com/MyOrg/MyProject/_git/myrepo.insteadOf`
        git_entries = config.strip.split("\n").select { |l| l.strip == "https://dev.azure.com/MyOrg/MyProject/myrepo.git" }
        expect(git_entries.length).to eq(1)
      end

      it "does not accumulate duplicate slash URL entries" do
        config = `git config --global --get-all url.https://dev.azure.com/MyOrg/MyProject/_git/myrepo/.insteadOf`
        slash_entries = config.strip.split("\n").select { |l| l.strip == "https://dev.azure.com/MyOrg/MyProject/myrepo/" }
        expect(slash_entries.length).to eq(1)
      end

      it "does not duplicate GOPRIVATE entries" do
        expect(ENV.fetch("GOPRIVATE", nil)).to eq("dev.azure.com")
      end
    end

    context "when GOPRIVATE already contains other entries" do
      before { ENV["GOPRIVATE"] = "github.com/private" }
      after { ENV.delete("GOPRIVATE") }

      it "appends dev.azure.com to existing GOPRIVATE" do
        described_class.configure_go_for_azure_devops("dev.azure.com/MyOrg/MyProject/myrepo")

        expect(ENV.fetch("GOPRIVATE", nil)).to eq("github.com/private,dev.azure.com")
      end
    end

    context "when GOPRIVATE already contains dev.azure.com" do
      before { ENV["GOPRIVATE"] = "dev.azure.com" }
      after { ENV.delete("GOPRIVATE") }

      it "does not duplicate dev.azure.com" do
        described_class.configure_go_for_azure_devops("dev.azure.com/MyOrg/MyProject/myrepo")

        expect(ENV.fetch("GOPRIVATE", nil)).to eq("dev.azure.com")
      end
    end

    context "when GOPRIVATE is wildcard" do
      before { ENV["GOPRIVATE"] = "*" }
      after { ENV.delete("GOPRIVATE") }

      it "does not modify GOPRIVATE" do
        described_class.configure_go_for_azure_devops("dev.azure.com/MyOrg/MyProject/myrepo")

        expect(ENV.fetch("GOPRIVATE", nil)).to eq("*")
      end
    end
  end
end
