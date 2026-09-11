# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/npm_and_yarn/file_parser/yarn_lock"

RSpec.describe Dependabot::NpmAndYarn::FileParser::YarnLock do
  subject(:reader) { described_class.new(file) }

  let(:file) { Dependabot::DependencyFile.new(name: "yarn.lock", content: "unused helper input") }
  let(:entry) { { "version" => "1.2.0", "resolution" => "example@npm:1.2.0" } }
  let(:result) { { "__metadata" => { "version" => 8 }, "example@^1.0.0, example@~1.2.0" => entry } }

  before do
    allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
      .with(hash_including(function: "yarn:parseLockfile")).and_return(result)
  end

  it "returns descriptor-keyed records without decoding control metadata" do
    expect(reader.parsed.keys).to eq(["example@^1.0.0, example@~1.2.0"])
    expect(reader.parsed.values.first.version).to eq("1.2.0")
  end

  it "preserves the sole-candidate lookup fallback" do
    expect(reader.details("example", "^9.0.0", "package.json"))
      .to have_attributes(version: "1.2.0", resolution: "example@npm:1.2.0")
  end

  context "with unconsumed malformed dependency data" do
    let(:entry) { super().merge("dependencies" => []) }

    it "does not read child requirements during dependency enumeration or lookup" do
      expect(reader.dependencies.dependencies.map(&:name)).to eq(["example"])
      expect(reader.details("example", nil, "package.json").version).to eq("1.2.0")
    end

    it "reports the field when relationship data is requested" do
      expect { reader.parsed.values.first.dependencies }
        .to raise_error(Dependabot::DependencyFileNotParseable, /dependencies must be an object/)
    end
  end

  context "with workspace descriptors" do
    let(:result) { super().merge("local@workspace:." => { "version" => "0.0.0-use.local", "dependencies" => {} }) }

    it "keeps workspace records available to graph readers" do
      expect(reader.parsed.keys).to include("local@workspace:.")
      expect(reader.dependencies.dependencies.map(&:name)).to eq(["example"])
    end
  end

  context "with malformed unused workspace fields" do
    let(:result) { { "local@workspace:." => { "version" => [], "dependencies" => false } } }

    it "skips workspace entries before consuming their fields" do
      expect(reader.dependencies.dependencies).to be_empty
    end
  end

  context "with a malformed version" do
    let(:entry) { super().merge("version" => 1) }

    it "reports the consumed field" do
      expect { reader.dependencies }
        .to raise_error(Dependabot::DependencyFileNotParseable, /version must be a string or nil/)
    end
  end

  context "with malformed child requirements" do
    let(:entry) { super().merge("dependencies" => { "child" => 1 }) }

    it "reports the child requirement type" do
      expect { reader.parsed.values.first.dependencies }
        .to raise_error(Dependabot::DependencyFileNotParseable, /dependencies.*child.*must be a string/)
    end
  end

  [nil, [], "invalid"].each do |value|
    context "with #{value.inspect} as the helper result" do
      let(:result) { value }

      it "reports the malformed root" do
        expect { reader.parsed }
          .to raise_error(Dependabot::DependencyFileNotParseable, /yarn helper result must be an object/)
      end
    end

    [
      ["No space left on device", Dependabot::OutOfDisk],
      ["Out of diskspace", Dependabot::OutOfDisk],
      ["MemoryError", Dependabot::OutOfMemory],
      ["invalid lockfile", Dependabot::DependencyFileNotParseable]
    ].each do |message, error_class|
      context "when the helper reports #{message}" do
        before do
          error = Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: message, error_context: {})
          allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
            .with(hash_including(function: "yarn:parseLockfile")).and_raise(error)
        end

        it "retains the existing error category" do
          expect { reader.parsed }.to raise_error(error_class)
        end
      end
    end
  end
end
