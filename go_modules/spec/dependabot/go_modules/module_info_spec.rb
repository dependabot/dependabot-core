# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/go_modules/module_info"

RSpec.describe Dependabot::GoModules::ModuleInfo do
  subject(:info) { described_class.from_json(content, command: command) }

  let(:command) { "go list -m -versions -json <dependency_name>" }
  let(:content) { JSON.generate(data) }
  let(:timestamp) { "2024-01-02T03:04:05.123456789+02:00" }
  let(:data) { { "Versions" => ["v1.2.0", "v2.0.0+incompatible"], "Time" => timestamp } }

  it "returns typed version strings and a parsed timestamp" do
    expect(info.versions).to eq(["v1.2.0", "v2.0.0+incompatible"])
    expect(info.released_at).to eq(Time.iso8601(timestamp))
    expect(info.released_at.nsec).to eq(123_456_789)
    expect(info.released_at.utc_offset).to eq(7200)
  end

  [{}, { "Versions" => nil, "Time" => nil }].each do |fields|
    context "with absent values #{fields}" do
      let(:data) { fields }

      it "preserves nil versions and time" do
        expect(info.versions).to be_nil
        expect(info.released_at).to be_nil
      end
    end
  end

  context "with an empty version list" do
    let(:data) { { "Versions" => [] } }

    it "distinguishes an empty list from an absent list" do
      expect(info.versions).to eq([])
    end
  end

  context "with unsorted, duplicate, and non-semver strings" do
    let(:data) { { "Versions" => ["v2.0.0", "", "main", "v1.0.0", "v2.0.0"] } }

    it "leaves filtering and ordering to the consumer" do
      expect(info.versions).to eq(data.fetch("Versions"))
    end
  end

  context "with a timestamp accepted by the existing parser" do
    let(:data) { { "Time" => "2024-01-02" } }

    it "retains Time.parse semantics" do
      expect(info.released_at).to eq(Time.parse("2024-01-02"))
    end
  end

  context "with unused fields" do
    let(:data) do
      super().merge("Path" => false, "Version" => [], "Replace" => 123, "Error" => {}, "Future" => [nil])
    end

    it "does not validate fields that the callers do not consume" do
      expect(info.versions).to eq(["v1.2.0", "v2.0.0+incompatible"])
      expect(info.released_at).to eq(Time.iso8601(timestamp))
    end
  end

  shared_examples "invalid module output" do |field|
    it "reports a safe command and field error without retaining the payload" do
      expect { info }.to raise_error(described_class::InvalidOutput) do |error|
        expect(error).to be_a(Dependabot::SharedHelpers::HelperSubprocessFailed)
        expect(error.message).to include(command, field)
        expect(error.message).not_to include("do-not-echo-this")
        expect(error.error_context).to eq(command: command)
        expect(error.cause).to be_nil
      end
    end
  end

  ['{"do-not-echo-this":', "{}\n{}"].each do |body|
    context "with invalid JSON #{body.inspect}" do
      let(:content) { body }

      it_behaves_like "invalid module output", "valid JSON"
    end
  end

  [nil, false, true, [], 123, "do-not-echo-this"].each do |value|
    context "with a non-object result #{value.inspect}" do
      let(:data) { value }

      it_behaves_like "invalid module output", "result must be an object"
    end
  end

  [false, true, {}, 123, "do-not-echo-this"].each do |value|
    context "with invalid Versions #{value.inspect}" do
      let(:data) { super().merge("Versions" => value) }

      it_behaves_like "invalid module output", "Versions must be an array or nil"
    end
  end

  [nil, false, true, [], {}, 123].each do |value|
    context "with a malformed trailing version #{value.inspect}" do
      let(:data) { super().merge("Versions" => ["v1.0.0", value]) }

      it_behaves_like "invalid module output", "Versions[1] must be a string"
    end
  end

  [false, true, [], {}, 123].each do |value|
    context "with invalid Time #{value.inspect}" do
      let(:data) { super().merge("Time" => value) }

      it_behaves_like "invalid module output", "Time must be a string or nil"
    end
  end

  ["", "do-not-echo-this"].each do |value|
    context "with an unparseable Time #{value.inspect}" do
      let(:data) { super().merge("Time" => value) }

      it_behaves_like "invalid module output", "Time must be a valid timestamp"
    end
  end

  context "when a version lookup includes a malformed timestamp" do
    let(:data) { { "Versions" => ["v1.0.0"], "Time" => false } }

    it_behaves_like "invalid module output", "Time"
  end

  context "when a timestamp lookup includes malformed versions" do
    let(:command) { "go list -m -json <dependency_name>" }
    let(:data) { { "Versions" => ["v1.0.0", false], "Time" => timestamp } }

    it_behaves_like "invalid module output", "Versions[1]"
  end
end
