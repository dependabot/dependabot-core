# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/pub/dependency_services_result"

RSpec.describe Dependabot::Pub::DependencyServicesResult do
  let(:listed_dependency) do
    {
      "name" => "example",
      "version" => "1.2.0",
      "kind" => "direct",
      "constraint" => ">= 1.0.0 < 2.0.0",
      "source" => { "type" => "sdk", "description" => "flutter", "unknown" => [nil, false] }
    }
  end
  let(:update) do
    {
      "name" => "example",
      "version" => "2.0.0",
      "kind" => "direct",
      "previousVersion" => "1.2.0",
      "previousConstraint" => "^1.0.0",
      "constraintBumped" => "^2.0.0",
      "constraintBumpedIfNeeded" => "^2.0.0",
      "constraintWidened" => ">=1.0.0 <3.0.0"
    }
  end
  let(:entry) do
    listed_dependency.merge(
      "latest" => "2.0.0",
      "compatible" => [],
      "singleBreaking" => [update],
      "multiBreaking" => [update],
      "unknown" => { "keep" => true }
    )
  end

  describe ".list_from_json" do
    subject(:dependencies) { described_class.list_from_json(JSON.dump("dependencies" => [listed_dependency])) }

    it "preserves strings and source-specific JSON" do
      expect(dependencies.first).to have_attributes(
        name: "example",
        version: "1.2.0",
        kind: "direct",
        constraint: ">= 1.0.0 < 2.0.0",
        source: listed_dependency["source"]
      )
    end

    context "with a Git revision" do
      let(:listed_dependency) { super().merge("version" => "a" * 40) }

      it "does not parse the revision as a semantic version" do
        expect(dependencies.first.version).to eq("a" * 40)
      end
    end

    context "without a constraint or source" do
      let(:listed_dependency) { super().except("constraint", "source") }

      it "preserves their absence" do
        expect(dependencies.first).to have_attributes(constraint: nil, source: nil)
      end
    end

    it "rejects the entire list when a later entry is malformed" do
      response = JSON.dump("dependencies" => [listed_dependency, nil])
      expect { described_class.list_from_json(response) }.to raise_error(
        Dependabot::SharedHelpers::HelperSubprocessFailed,
        "dependency_services list.dependencies[1] must be an object"
      )
    end
  end

  describe ".report_from_json" do
    subject(:report) { described_class.report_from_json(JSON.dump("dependencies" => entries)) }

    let(:entries) { [entry] }

    it "returns typed reports and updates while keeping the cache payload unchanged" do
      expect(report.dependencies.first).to have_attributes(
        name: "example", version: "1.2.0", latest: "2.0.0", compatible: [], smallest_update: nil
      )
      expect(report.dependencies.first.single_breaking.first).to have_attributes(
        name: "example",
        version: "2.0.0",
        kind: "direct",
        previous_version: "1.2.0",
        previous_constraint: "^1.0.0",
        constraint_bumped: "^2.0.0",
        constraint_bumped_if_needed: "^2.0.0",
        constraint_widened: ">=1.0.0 <3.0.0"
      )
      expect(JSON.parse(report.cache_content)).to eq(entries)
    end

    it "decodes cache hits into the same typed values" do
      cached = described_class.report_from_cache(report.cache_content)
      expect(cached.dependencies.first.single_breaking.first.version).to eq("2.0.0")
      expect(cached.cache_content).to eq(report.cache_content)
    end

    context "with removed and added dependencies" do
      let(:entry) do
        super().merge(
          "multiBreaking" => [
            update.merge("name" => "removed", "kind" => "transitive", "version" => nil),
            update.merge("name" => "added", "previousVersion" => nil)
          ]
        )
      end

      it "preserves both meanings of null" do
        removed, added = report.dependencies.first.multi_breaking
        expect(removed).to have_attributes(name: "removed", version: nil, previous_version: "1.2.0")
        expect(added).to have_attributes(name: "added", version: "2.0.0", previous_version: nil)
      end
    end

    context "with an explicit empty security result" do
      let(:entry) { super().merge("smallestUpdate" => []) }

      it "does not turn it into an absent result" do
        expect(report.dependencies.first.smallest_update).to eq([])
      end
    end

    context "with a null security result" do
      let(:entry) { super().merge("smallestUpdate" => nil) }

      it "requires an array when the field is present" do
        expect { report }.to raise_error(
          Dependabot::SharedHelpers::HelperSubprocessFailed,
          "dependency_services report.dependencies[0].smallestUpdate must be an array"
        )
      end
    end

    context "with duplicate reports and updates" do
      let(:entries) { [entry, entry] }
      let(:entry) { super().merge("compatible" => [update, update.merge("name" => "other"), update]) }

      it "preserves their order and duplicates" do
        expect(report.dependencies.map(&:name)).to eq(%w(example example))
        expect(report.dependencies.first.compatible.map(&:name)).to eq(%w(example other example))
      end
    end

    invalid_arrays = [nil, "invalid", {}, false]
    %w(compatible singleBreaking multiBreaking).each do |field|
      invalid_arrays.each do |value|
        context "with #{field} set to #{value.inspect}" do
          let(:entry) { super().merge(field => value) }

          it "identifies the required solution array" do
            expect { report }.to raise_error(
              Dependabot::SharedHelpers::HelperSubprocessFailed,
              "dependency_services report.dependencies[0].#{field} must be an array"
            )
          end
        end
      end

      context "without #{field}" do
        let(:entry) { super().except(field) }

        it "does not invent an empty solution" do
          expect { report }.to raise_error(
            Dependabot::SharedHelpers::HelperSubprocessFailed,
            "dependency_services report.dependencies[0].#{field} must be an array"
          )
        end
      end
    end

    context "with a malformed later update" do
      let(:entry) { super().merge("singleBreaking" => [update, update.merge("version" => false)]) }

      it "validates every update before returning a report" do
        expect { report }.to raise_error(
          Dependabot::SharedHelpers::HelperSubprocessFailed,
          "dependency_services report.dependencies[0].singleBreaking[1].version must be a string or nil"
        )
      end
    end

    context "with no latest candidate" do
      let(:entry) { super().merge("latest" => nil) }

      it "retains the missing candidate" do
        expect(report.dependencies.first.latest).to be_nil
      end
    end
  end

  describe ".report_from_cache" do
    ["not json", "{}", "[null]"].each do |content|
      context "with cache content #{content.inspect}" do
        it "raises a contextual error without a raw-payload cause" do
          expect { described_class.report_from_cache(content) }.to raise_error(
            Dependabot::SharedHelpers::HelperSubprocessFailed, /dependency_services report cache/
          ) do |error|
            expect(error.cause).to be_nil
          end
        end
      end
    end
  end

  describe ".find_report" do
    it "reports a missing required target explicitly" do
      report = described_class.report_from_json(JSON.dump("dependencies" => [entry]))
      expect { described_class.find_report(report.dependencies, "missing") }.to raise_error(
        Dependabot::SharedHelpers::HelperSubprocessFailed,
        "dependency_services report does not include the requested dependency"
      )
    end
  end
end
