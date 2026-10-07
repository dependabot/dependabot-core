# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/file_parser/pep_dependency"

RSpec.describe Dependabot::Python::FileParser::PepDependency do
  describe ".from_helper_result" do
    subject(:dependencies) { described_class.from_helper_result(result) }

    let(:result) do
      [{
        "name" => "cachecontrol",
        "version" => nil,
        "markers" => "python_version >= \"3.9\"",
        "file" => "pyproject.toml",
        "requirement" => ">=0.14.0",
        "source_requirement" => ">= 0.14.0",
        "extras" => ["filecache"],
        "requirement_type" => "dependencies",
        "unknown" => true
      }]
    end

    it "parses supported fields and ignores unknown keys" do
      expect(dependencies.first).to have_attributes(
        name: "cachecontrol",
        version: nil,
        markers: "python_version >= \"3.9\"",
        file: "pyproject.toml",
        requirement: ">=0.14.0",
        source_requirement: ">= 0.14.0",
        extras: ["filecache"],
        requirement_type: "dependencies"
      )
    end

    context "with a UV path dependency" do
      let(:result) do
        [{
          "name" => "local-package",
          "version" => nil,
          "markers" => nil,
          "file" => "pyproject.toml",
          "requirement" => nil,
          "extras" => [],
          "path_dependency" => true,
          "path" => "../local-package"
        }]
      end

      it "allows a nil requirement" do
        expect(dependencies.first).to have_attributes(
          name: "local-package",
          requirement: nil,
          extras: []
        )
      end
    end

    [
      [nil, "PEP dependency result must be an array"],
      [[{}], "PEP dependency name must be a string"],
      [[{
        "name" => "requests",
        "file" => "pyproject.toml",
        "requirement" => ">=2",
        "extras" => [1]
      }], "PEP dependency extras must contain only strings"]
    ].each do |invalid_result, message|
      context "with #{message}" do
        let(:result) { invalid_result }

        it "raises an explicit type error" do
          expect { dependencies }.to raise_error(TypeError, message)
        end
      end
    end
  end

  describe ".from_requirements_helper_result" do
    subject(:dependencies) { described_class.from_requirements_helper_result(result) }

    let(:record) do
      {
        "name" => "requests",
        "version" => "2.31.0",
        "markers" => "None",
        "file" => "requirements.txt",
        "requirement" => "==2.31.0",
        "extras" => ["security"],
        "unknown" => true
      }
    end
    let(:result) { [record] }

    it "returns typed records without changing the helper fields" do
      expect(dependencies.first).to be_a(described_class)
      expect(dependencies.first).to have_attributes(
        name: "requests",
        version: "2.31.0",
        markers: "None",
        file: "requirements.txt",
        requirement: "==2.31.0",
        extras: ["security"],
        source_requirement: nil,
        requirement_type: nil
      )
    end

    context "with an empty result" do
      let(:result) { [] }

      it "returns no records" do
        expect(dependencies).to be_empty
      end
    end

    context "with multiple records" do
      let(:result) { [record, record.merge("name" => "urllib3"), record] }

      it "preserves order and duplicate records" do
        expect(dependencies.map(&:name)).to eq(%w(requests urllib3 requests))
      end
    end

    context "without optional fields" do
      let(:record) { super().except("version", "markers", "requirement").merge("extras" => []) }

      it "uses nil for the missing fields" do
        expect(dependencies.first).to have_attributes(version: nil, markers: nil, requirement: nil, extras: [])
      end
    end

    context "with null optional fields" do
      let(:record) { super().merge("version" => nil, "markers" => nil, "requirement" => nil) }

      it "preserves null fields" do
        expect(dependencies.first).to have_attributes(version: nil, markers: nil, requirement: nil)
      end
    end

    context "with empty strings" do
      let(:record) { super().merge("version" => "", "markers" => "", "requirement" => "") }

      it "does not coerce them to nil" do
        expect(dependencies.first).to have_attributes(version: "", markers: "", requirement: "")
      end
    end

    [nil, {}, "invalid", 1].each do |value|
      context "with #{value.inspect} as the result" do
        let(:result) { value }

        it "reports a malformed requirements result" do
          expect { dependencies }.to raise_error(
            Dependabot::DependencyFileNotEvaluatable,
            "parse_requirements result must be an array"
          )
        end
      end
    end

    [nil, [], "invalid", 1].each do |value|
      context "with #{value.inspect} as a record" do
        let(:result) { [record, value] }

        it "identifies the malformed record" do
          expect { dependencies }.to raise_error(
            Dependabot::DependencyFileNotEvaluatable,
            /parse_requirements result\[1\].*must be an object/
          )
        end
      end
    end

    %w(name file extras).each do |field|
      context "without #{field}" do
        let(:record) { super().except(field) }

        it "identifies the missing field" do
          expect { dependencies }.to raise_error(
            Dependabot::DependencyFileNotEvaluatable,
            /parse_requirements result\[0\].*#{field}/
          )
        end
      end
    end

    [
      ["name", 1],
      ["file", false],
      ["version", []],
      ["markers", 1],
      ["requirement", false],
      ["extras", nil],
      %w(extras not-an-extra-list),
      ["extras", [1]]
    ].each do |field, value|
      context "with #{field} set to #{value.inspect}" do
        let(:record) { super().merge(field => value) }

        it "identifies the field without echoing the helper response" do
          expect { dependencies }.to raise_error(
            Dependabot::DependencyFileNotEvaluatable,
            /parse_requirements result\[0\].*#{field}/
          ) do |error|
            expect(error.message).not_to include("not-an-extra-list")
          end
        end
      end
    end

    context "with a non-string key" do
      let(:record) { super().merge(1 => "unknown") }

      it "identifies the record's key type" do
        expect { dependencies }.to raise_error(
          Dependabot::DependencyFileNotEvaluatable,
          /parse_requirements result\[0\].*keys must be strings/
        )
      end
    end
  end
end
