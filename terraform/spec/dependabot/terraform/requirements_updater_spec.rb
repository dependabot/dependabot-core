# typed: false
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
    subject(:updated_requirements) { updater.updated_requirements.first }

    specify { expect(updater.updated_requirements.count).to eq(1) }

    context "when there is a latest version" do
      let(:latest_version) { version_class.new("0.3.7") }

      context "when no requirement was previously specified" do
        let(:requirement) { nil }

        it { is_expected.to eq(requirements.first) }
      end

      context "when an exact requirement was previously specified" do
        let(:requirement) { "0.3.1" }

        its([:requirement]) { is_expected.to eq("0.3.7") }

        context "when a pre-release version" do
          let(:latest_version) { version_class.new("0.3.7-pre") }

          its([:requirement]) { is_expected.to eq("0.3.7-pre") }
        end
      end

      context "when a ~> requirement was previously specified" do
        context "when satisfied" do
          let(:requirement) { "~> 0.3.1" }

          it { is_expected.to eq(requirements.first) }
        end

        context "when not satisfied" do
          let(:requirement) { "~> 0.2.1" }

          its([:requirement]) { is_expected.to eq("~> 0.3.7") }

          context "when specifying two digits" do
            let(:requirement) { "~> 0.2" }
            let(:latest_version) { "1.1.0" }

            its([:requirement]) { is_expected.to eq("~> 1.1") }
          end
        end
      end

      context "when <= requirement was previously specified" do
        context "when it is satisfied" do
          let(:requirement) { "<= 0.3.7" }

          it { is_expected.to eq(requirements.first) }
        end

        context "when it is not satisfied" do
          let(:requirement) { "<= 0.1.9" }

          its([:requirement]) { is_expected.to eq("<= 0.3.7") }

          context "when specifying two version segments" do
            let(:requirement) { "<= 0.3" }
            let(:latest_version) { version_class.new("2.8.5") }

            its([:requirement]) { is_expected.to eq("<= 2.8.5") }
          end

          context "when specifying three version segments" do
            let(:requirement) { "<= 0.3.7" }
            let(:latest_version) { version_class.new("2.8.5") }

            its([:requirement]) { is_expected.to eq("<= 2.8.5") }
          end

          context "when minor and patch updated" do
            let(:requirement) { "<= 0.3.7" }
            let(:latest_version) { version_class.new("0.4.0") }

            its([:requirement]) { is_expected.to eq("<= 0.4.0") }
          end

          context "when major, minor and patch updated" do
            let(:requirement) { "<= 0.3.7" }
            let(:latest_version) { version_class.new("1.4.0") }

            its([:requirement]) { is_expected.to eq("<= 1.4.0") }
          end
        end
      end

      context "when a =>,<,<= requirement was previously specified" do
        context "when satisfied" do
          let(:requirement) { ">= 0.2.1, < 0.4.0" }
          let(:latest_version) { "0.3.7" }

          its([:requirement]) { is_expected.to eq(">= 0.2.1, < 0.4.0") }
        end

        context "when not satisfied, 0 patch version" do
          let(:requirement) { ">= 0.2.1, < 0.3.0, <= 0.3.0" }
          let(:latest_version) { "0.3.7" }

          its([:requirement]) { is_expected.to eq(">= 0.2.1, < 0.3.8, <= 0.3.7") }
        end

        context "when not satisfied, non-0 patch version" do
          let(:requirement) { ">= 0.2.1, < 0.3.2, <= 0.3.2" }
          let(:latest_version) { "0.3.7" }

          its([:requirement]) { is_expected.to eq(">= 0.2.1, < 0.3.8, <= 0.3.7") }
        end

        context "when not satisfied, major and minor only" do
          let(:requirement) { ">= 0.2.1, < 0.3, <= 0.3" }
          let(:latest_version) { "0.3.7" }

          its([:requirement]) { is_expected.to eq(">= 0.2.1, < 0.4, <= 0.3.7") }
        end

        context "when not satisfied, major and minor only" do
          let(:requirement) { ">= 0.2.1, < 0.3, <= 0.3" }
          let(:latest_version) { "1.4.0" }

          its([:requirement]) { is_expected.to eq(">= 0.2.1, < 1.5, <= 1.4.0") }
        end
      end
    end

    context "when dealing with a git requirement" do
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
        expect(updated_requirements.dig(:source, :ref)).to eq("tags/0.4.1")
      end

      it "does not touch the requirement" do
        expect(updated_requirements[:requirement]).to be_nil
      end
    end
  end
end
