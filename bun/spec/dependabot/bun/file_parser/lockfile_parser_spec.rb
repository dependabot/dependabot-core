# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun"

RSpec.describe Dependabot::Bun::FileParser::LockfileParser do
  subject(:lockfile_parser) do
    described_class.new(dependency_files: dependency_files)
  end

  describe "#parse" do
    subject(:dependencies) { lockfile_parser.parse }

    context "when dealing with bun.lock" do
      context "when the lockfile is invalid" do
        let(:dependency_files) { project_dependency_files("bun/invalid_lockfile") }

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("bun.lock")
              expect(error.message).to eq("Invalid bun.lock file: malformed JSONC at line 3, column 1")
            end
        end
      end

      context "when the lockfile version is invalid" do
        let(:dependency_files) { project_dependency_files("bun/invalid_lockfile_version") }

        it "raises a DependencyFileNotParseable error" do
          expect { dependencies }
            .to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("bun.lock")
              expect(error.message).to include("lockfileVersion")
            end
        end
      end

      context "when dealing with v0 format" do
        context "with a simple project" do
          let(:dependency_files) { project_dependency_files("bun/simple_v0") }

          it "parses dependencies properly" do
            expect(dependencies.find { |d| d.name == "fetch-factory" }).to have_attributes(
              name: "fetch-factory",
              version: "0.0.1"
            )
            expect(dependencies.find { |d| d.name == "etag" }).to have_attributes(
              name: "etag",
              version: "1.8.1"
            )
            expect(dependencies.length).to eq(11)
          end
        end

        context "with a simple workspace project" do
          let(:dependency_files) { project_dependency_files("bun/simple_workspace_v0") }

          it "parses dependencies properly" do
            expect(dependencies.find { |d| d.name == "etag" }).to have_attributes(
              name: "etag",
              version: "1.8.1"
            )
            expect(dependencies.find { |d| d.name == "lodash" }).to have_attributes(
              name: "lodash",
              version: "1.3.1"
            )
            expect(dependencies.find { |d| d.name == "chalk" }).to have_attributes(
              name: "chalk",
              version: "0.3.0"
            )
            expect(dependencies.length).to eq(5)
          end
        end
      end

      context "when dealing with v1 format" do
        let(:dependency_files) { project_dependency_files("bun/simple_v1") }

        it "parses dependencies properly" do
          expect(dependencies.find { |d| d.name == "fetch-factory" }).to have_attributes(
            name: "fetch-factory",
            version: "0.0.1"
          )
          expect(dependencies.find { |d| d.name == "etag" }).to have_attributes(
            name: "etag",
            version: "1.8.1"
          )
          expect(dependencies.length).to eq(17)
        end
      end
    end
  end
end
