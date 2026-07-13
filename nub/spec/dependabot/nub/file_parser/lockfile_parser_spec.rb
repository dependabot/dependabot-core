# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/nub"

RSpec.describe Dependabot::Nub::FileParser::LockfileParser do
  subject(:lockfile_parser) do
    described_class.new(dependency_files: dependency_files)
  end

  describe "#parse" do
    subject(:dependencies) { lockfile_parser.parse }

    # nub.lock is a pnpm-lock v9 document; it is parsed via the shared pnpm parseLockfile helper.
    context "when dealing with a valid nub.lock" do
      let(:dependency_files) { project_dependency_files("nub/simple_v1") }

      it "parses the top-level dependencies" do
        expect(dependencies.find { |d| d.name == "fetch-factory" }).to have_attributes(
          name: "fetch-factory",
          version: "0.0.1"
        )
        expect(dependencies.find { |d| d.name == "etag" }).to have_attributes(
          name: "etag",
          version: "1.8.1"
        )
      end

      it "parses transitive dependencies from the snapshots section" do
        expect(dependencies.find { |d| d.name == "lodash" }).to have_attributes(
          name: "lodash",
          version: "3.10.1"
        )
      end
    end

    context "when the lockfile is not parseable pnpm-lock v9" do
      let(:dependency_files) do
        [
          Dependabot::DependencyFile.new(
            name: "package.json",
            content: '{"dependencies": {"etag": "^1.0.0"}}'
          ),
          Dependabot::DependencyFile.new(
            name: "nub.lock",
            content: ":\n  not: valid: pnpm: lock: ["
          )
        ]
      end

      it "raises a DependencyFileNotParseable error naming nub.lock" do
        expect { dependencies }
          .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
            expect(error.file_name).to eq("nub.lock")
          end
      end
    end
  end
end
