# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/sbt/update_checker/requirements_updater"

RSpec.describe Dependabot::Sbt::UpdateChecker::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      latest_version: latest_version,
      source_url: "https://repo.maven.apache.org/maven2",
      properties_to_update: properties_to_update
    )
  end

  let(:version_class) { Dependabot::Sbt::Version }
  let(:requirements) { [sbt_req] }
  let(:properties_to_update) { [] }

  let(:sbt_req) do
    {
      file: "build.sbt",
      requirement: sbt_req_string,
      groups: [],
      source: nil,
      metadata: nil
    }
  end
  let(:sbt_req_string) { "2.10.0" }
  let(:latest_version) { version_class.new("2.12.0") }

  describe "#updated_requirements" do
    subject(:updated_requirements) { updater.updated_requirements }

    specify { expect(updated_requirements.count).to eq(1) }

    context "when there is no latest version" do
      let(:latest_version) { nil }

      it "returns the existing requirements unchanged" do
        expect(updated_requirements.first).to eq(sbt_req)
      end
    end

    context "when there is a latest version" do
      let(:latest_version) { version_class.new("2.12.0") }

      context "with a simple exact version" do
        let(:sbt_req_string) { "2.10.0" }

        its(:first) do
          is_expected.to eq(
            file: "build.sbt",
            requirement: "2.12.0",
            groups: [],
            source: { type: "maven_repo", url: "https://repo.maven.apache.org/maven2" },
            metadata: nil
          )
        end
      end

      context "with a nil requirement" do
        let(:sbt_req_string) { nil }

        it "returns the requirement unchanged" do
          expect(updated_requirements.first).to eq(sbt_req)
        end
      end

      context "with a jre-suffixed version" do
        let(:sbt_req_string) { "33.0.0-jre" }
        let(:latest_version) { version_class.new("33.4.0-jre") }

        its(:first) do
          is_expected.to include(requirement: "33.4.0-jre")
        end
      end

      context "with a range requirement (comma-separated)" do
        let(:sbt_req_string) { "[2.10.0,2.11.0]" }

        it "does not update range requirements" do
          expect(updated_requirements.first).to eq(sbt_req)
        end
      end
    end

    context "with property-based requirements" do
      let(:sbt_req) do
        {
          file: "build.sbt",
          requirement: "2.10.0",
          groups: [],
          source: nil,
          metadata: { property_name: "catsVersion", property_source: "build.sbt" }
        }
      end

      context "when the property is in properties_to_update" do
        let(:properties_to_update) { ["catsVersion"] }

        its(:first) do
          is_expected.to include(requirement: "2.12.0")
        end
      end

      context "when the property is NOT in properties_to_update" do
        let(:properties_to_update) { [] }

        it "does not update the requirement" do
          expect(updated_requirements.first[:requirement]).to eq("2.10.0")
        end
      end
    end

    context "with multiple requirements" do
      let(:requirements) { [sbt_req, other_req] }
      let(:other_req) do
        {
          file: "project/plugins.sbt",
          requirement: "2.10.0",
          groups: ["plugins"],
          source: nil,
          metadata: nil
        }
      end

      it "updates both requirements" do
        expect(updated_requirements.count).to eq(2)
        expect(updated_requirements[0][:requirement]).to eq("2.12.0")
        expect(updated_requirements[1][:requirement]).to eq("2.12.0")
      end
    end
  end
end
