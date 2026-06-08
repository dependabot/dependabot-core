# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/helm/helpers"

RSpec.describe Dependabot::Helm::Helpers do
  describe ".add_repo" do
    it "uses '--' to terminate flags" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        "helm repo add -- test-repo https://example.com/charts",
        fingerprint: "helm repo add -- <repo_name> <repository_url>"
      ).and_return("")

      described_class.add_repo("test-repo", "https://example.com/charts")
      expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
        "helm repo add -- test-repo https://example.com/charts",
        fingerprint: "helm repo add -- <repo_name> <repository_url>"
      )
    end

    it "rejects injected repository URL flags" do
      expect do
        described_class.add_repo("test-repo", "https://example.com/charts --pass-credentials")
      end.to raise_error(ArgumentError, "Invalid repository_url")
    end
  end

  describe ".fetch_oci_tags" do
    it "uses '--' to terminate flags" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        "oras repo tags -- registry.example.com/charts/mychart",
        fingerprint: "oras repo tags -- <name>"
      ).and_return("1.2.3")

      expect(described_class.fetch_oci_tags("registry.example.com/charts/mychart")).to eq("1.2.3")
      expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
        "oras repo tags -- registry.example.com/charts/mychart",
        fingerprint: "oras repo tags -- <name>"
      )
    end

    it "rejects injected flags" do
      expect { described_class.fetch_oci_tags("--format json") }.to raise_error(ArgumentError, "Invalid name")
    end
  end

  describe ".fetch_tags_with_release_date_using_oci" do
    it "uses '--' to terminate flags" do
      allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
        "oras manifest fetch -- registry.example.com/charts/mychart:1.2.3",
        fingerprint: "oras manifest fetch -- <repo_url>:<tag>"
      ).and_return("{}")

      expect(described_class.fetch_tags_with_release_date_using_oci("registry.example.com/charts/mychart", "1.2.3"))
        .to eq("{}")
      expect(Dependabot::SharedHelpers).to have_received(:run_shell_command).with(
        "oras manifest fetch -- registry.example.com/charts/mychart:1.2.3",
        fingerprint: "oras manifest fetch -- <repo_url>:<tag>"
      )
    end

    it "rejects injected tag flags" do
      expect do
        described_class.fetch_tags_with_release_date_using_oci(
          "registry.example.com/charts/mychart",
          "1.2.3 --output json"
        )
      end.to raise_error(ArgumentError, "Invalid tag")
    end
  end
end
