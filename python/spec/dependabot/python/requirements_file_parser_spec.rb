# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/python/requirements_file_parser"

RSpec.describe Dependabot::Python::RequirementsFileParser do
  let(:result) do
    {
      "schema_version" => 1,
      "declarations" => [
        {
          "name" => "requests",
          "version" => "2.31.0",
          "markers" => nil,
          "file" => "requirements.txt",
          "requirement" => "==2.31.0",
          "source_requirement" => "requests==2.31.0",
          "extras" => [],
          "constraint" => false,
          "editable" => false,
          "local" => false,
          "hashes" => ["sha256:abc"],
          "source" => { "start_line" => 2, "end_line" => 3 }
        }
      ],
      "files" => [
        { "path" => "requirements.txt", "component_id" => "component-0" },
        { "path" => "base.txt", "component_id" => "component-0" }
      ],
      "edges" => [
        {
          "from" => "requirements.txt",
          "to" => "base.txt",
          "type" => "requirement",
          "remote" => false,
          "source" => { "start_line" => 1, "end_line" => 1 }
        }
      ],
      "roots" => ["requirements.txt"],
      "components" => [
        {
          "id" => "component-0",
          "files" => ["base.txt", "requirements.txt"],
          "roots" => ["requirements.txt"],
          "status" => "complete",
          "reasons" => [],
          "has_index_options" => false,
          "source_spans_applicable" => true
        }
      ]
    }
  end

  describe ".from_helper_result" do
    subject(:parsed) { described_class.from_helper_result(result) }

    it "builds typed declarations and graph records" do
      expect(parsed.schema_version).to eq(1)
      expect(parsed.declarations.first).to have_attributes(
        name: "requests",
        hashes: ["sha256:abc"],
        source: have_attributes(start_line: 2, end_line: 3)
      )
      expect(parsed.components.first).to be_complete
      expect(parsed.components.first.has_index_options).to be(false)
      expect(parsed.components.first.source_spans_applicable).to be(true)
    end

    it "walks exact local edges" do
      expect(parsed.local_paths_from("requirements.txt")).to eq(["base.txt"])
      expect(parsed.reachable_local_files(["requirements.txt"]))
        .to contain_exactly("requirements.txt", "base.txt")
    end

    context "with an unknown schema version" do
      let(:result) { super().merge("schema_version" => 2) }

      it "fails as an internal helper contract error" do
        expect { parsed }
          .to raise_error(Dependabot::Python::InvalidRequirementsFileParserResult, /schema_version 2/)
      end
    end

    context "with an invalid nested record" do
      let(:result) do
        super().merge(
          "components" => [
            super()["components"].first.merge("reasons" => ["new_unhandled_reason"])
          ]
        )
      end

      it "does not silently accept unknown helper policy facts" do
        expect { parsed }
          .to raise_error(Dependabot::Python::InvalidRequirementsFileParserResult, /unknown reasons/)
      end
    end

    context "with a local edge to an unknown file" do
      let(:result) do
        super().merge(
          "edges" => [
            super()["edges"].first.merge("to" => "missing.txt")
          ]
        )
      end

      it "rejects the inconsistent graph" do
        expect { parsed }
          .to raise_error(Dependabot::Python::InvalidRequirementsFileParserResult, /unknown target/)
      end
    end
  end

  describe "#parse" do
    subject(:parse) { parser.parse }

    let(:parser) { described_class.new(dependency_files: [requirements]) }
    let(:requirements) do
      Dependabot::DependencyFile.new(name: "requirements.txt", content: "requests==2.31.0\n")
    end

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
        .with(hash_including(function: "parse_requirements_v2")).and_return(result)
    end

    it "returns the validated helper result" do
      expect(parse.declarations.map(&:name)).to eq(["requests"])
    end

    context "when pip reports malformed input" do
      let(:helper_error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "RequirementsFileParseError: invalid input",
          error_context: {}
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
          .with(hash_including(function: "parse_requirements_v2")).and_raise(helper_error)
      end

      it "maps the known pip error to a user-facing evaluation error" do
        expect { parse }
          .to raise_error(Dependabot::DependencyFileNotEvaluatable, "RequirementsFileParseError: invalid input")
      end
    end

    context "when the helper fails unexpectedly" do
      let(:helper_error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(
          message: "Unexpected helper failure",
          error_context: {}
        )
      end

      before do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
          .with(hash_including(function: "parse_requirements_v2")).and_raise(helper_error)
      end

      it "preserves the unexpected helper failure" do
        expect { parse }.to raise_error(helper_error)
      end
    end
  end
end
