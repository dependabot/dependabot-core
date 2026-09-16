# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/package/npm_lockfile_details"

RSpec.describe Dependabot::Package::NpmLockfileDetails do
  describe ".from_object" do
    subject(:details) { described_class.from_object(value, path: path, context: "chalk") }

    let(:path) { "nested/package-lock.json" }
    let(:value) do
      {
        "version" => "1.0.0",
        "resolved" => "https://registry.example/chalk.tgz",
        "resolution" => "chalk@npm:1.0.0",
        "dependencies" => ["unconsumed"]
      }
    end

    it "exposes only the typed lookup fields" do
      expect(details).to have_attributes(
        version: "1.0.0",
        resolved: "https://registry.example/chalk.tgz",
        resolution: "chalk@npm:1.0.0"
      )
    end

    context "with an empty entry" do
      let(:value) { {} }

      it "retains the presence of an unresolved entry" do
        expect(details).to be_a(described_class)
        expect(details).to have_attributes(version: nil, resolved: nil, resolution: nil)
      end
    end

    context "with null fields" do
      let(:value) { { "version" => nil, "resolved" => nil, "resolution" => nil } }

      it "preserves them" do
        expect(details).to have_attributes(version: nil, resolved: nil, resolution: nil)
      end
    end

    context "with empty and non-semver strings" do
      let(:value) { { "version" => "git+https://example/repo#ref", "resolved" => "", "resolution" => "" } }

      it "does not normalize their contents" do
        expect(details).to have_attributes(version: "git+https://example/repo#ref", resolved: "", resolution: "")
      end
    end

    [nil, [], "invalid", false].each do |invalid_value|
      context "with #{invalid_value.inspect} instead of an entry" do
        let(:value) { invalid_value }

        it "identifies the file and entry" do
          expect { details }
            .to raise_error(Dependabot::DependencyFileNotParseable, "chalk must be an object") do |error|
              expect(error.file_path).to eq(path)
            end
        end
      end
    end

    [["version", 1], ["resolved", false], ["resolution", {}]].each do |field, invalid_value|
      context "with malformed #{field}" do
        let(:value) { { field => invalid_value } }

        it "identifies the consumed field" do
          expect { details }
            .to raise_error(
              Dependabot::DependencyFileNotParseable,
              "chalk.#{field} must be a string or nil"
            ) do |error|
              expect(error.file_path).to eq(path)
            end
        end
      end
    end
  end
end
