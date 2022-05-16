# frozen_string_literal: true

require "spec_helper"
require "dependabot/terraform/version"
require "dependabot/terraform/requirements_updater"

RSpec.describe Dependabot::Terraform::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      latest_version: latest_version,
      tag_for_latest_version: tag_for_latest_version
    )
  end

  let(:requirements) do
    [{ requirement: requirement, groups: [], file: "main.tf", source: source }]
  end
  let(:latest_version) { version_class.new("0.3.7") }
  let(:tag_for_latest_version) { nil }

  let(:version_class) { Dependabot::Terraform::Version }
  let(:requirement) { "~> 0.2.1" }
  let(:source) do
    {
      type: "registry",
      registry_hostname: "registry.terraform.io",
      module_identifier: "hashicorp/consul/aws"
    }
  end

  describe "#updated_requirements" do
    subject { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    context "when there is no latest version" do
      let(:latest_version) { nil }
      it { is_expected.to eq(requirements.first) }
    end

    context "when there is a latest version" do
      let(:latest_version) { version_class.new("0.3.7") }

      context "and no requirement was previously specified" do
        let(:requirement) { nil }
        it { is_expected.to eq(requirements.first) }
      end

      context "and an exact requirement was previously specified" do
        let(:requirement) { "0.3.1" }
        its([:requirement]) { is_expected.to eq("0.3.7") }

        context "and a pre-release version" do
          let(:latest_version) { version_class.new("0.3.7-pre") }
          its([:requirement]) { is_expected.to eq("0.3.7-pre") }
        end
      end

      context "and a ~> requirement was previously specified" do
        context "that is satisfied" do
          let(:requirement) { "~> 0.3.1" }
          it { is_expected.to eq(requirements.first) }
        end

        context "that is not satisfied" do
          let(:requirement) { "~> 0.2.1" }
          its([:requirement]) { is_expected.to eq("~> 0.3.7") }

          context "specifying two digits" do
            let(:requirement) { "~> 0.2" }
            let(:latest_version) { "1.1.0" }
            its([:requirement]) { is_expected.to eq("~> 1.1") }
          end
        end
      end

      context "and a =>,< requirement was previously specified" do
        context "that is satisfied" do
          let(:requirement) { ">= 0.2.1, < 0.4.0" }
          let(:latest_version) { "0.3.7" }
          its([:requirement]) { is_expected.to eq(">= 0.2.1, < 0.4.0") }
        end
        context "that is not satisfied" do
          let(:requirement) { ">= 0.2.1, < 0.3.0" }
          let(:latest_version) { "0.3.7" }
          its([:requirement]) { is_expected.to eq(">= 0.2.1, < 0.4.0") }
        end
      end
    end

    context "for a git requirement" do
      let(:latest_version) { "0.4.1" }
      let(:tag_for_latest_version) { "tags/0.4.1" }
      let(:requirements) do
        [
          {
            requirement: nil,
            groups: [],
            file: "main.tf",
            source: {
              type: "git",
              url: "https://github.com/cloudposse/terraform-null-label.git",
              branch: nil,
              ref: "tags/0.3.7"
            }
          }
        ]
      end

      it "updates the source ref" do
        expect(subject.dig(:source, :ref)).to eq("tags/0.4.1")
      end

      it "does not touch the requirement" do
        expect(subject[:requirement]).to be_nil
      end
    end
  end
end
