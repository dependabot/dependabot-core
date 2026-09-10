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
end
