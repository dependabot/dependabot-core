# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/python/file_parser/setup_cfg_file_parser"

RSpec.describe Dependabot::Python::FileParser::SetupCfgFileParser do
  let(:parser) { described_class.new(dependency_files: files) }

  let(:files) { [setup_cfg_file] }
  let(:setup_cfg_file) do
    Dependabot::DependencyFile.new(
      name: "setup.cfg",
      content: setup_cfg_file_body
    )
  end
  let(:setup_cfg_file_body) do
    fixture("setup_files", setup_cfg_file_fixture_name)
  end
  let(:setup_cfg_file_fixture_name) { "setup_with_requires.cfg" }

  describe "parse" do
    subject(:dependencies) { parser.dependency_set.dependencies }

    its(:length) { is_expected.to eq(15) }

    describe "an install_requires dependencies" do
      subject(:dependency) { dependencies.find { |d| d.name == "boto3" } }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("boto3")
        expect(dependency.version).to eq("1.3.1")
        expect(dependency.requirements).to eq(
          [{
            requirement: "==1.3.1",
            file: "setup.cfg",
            groups: ["install_requires"],
            source: nil
          }]
        )
      end
    end

    describe "a setup_requires dependencies" do
      subject(:dependency) { dependencies.find { |d| d.name == "numpy" } }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("numpy")
        expect(dependency.version).to eq("1.11.0")
        expect(dependency.requirements).to eq(
          [{
            requirement: "==1.11.0",
            file: "setup.cfg",
            groups: ["setup_requires"],
            source: nil
          }]
        )
      end
    end

    describe "a tests_require dependencies" do
      subject(:dependency) { dependencies.find { |d| d.name == "responses" } }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("responses")
        expect(dependency.version).to eq("0.5.1")
        expect(dependency.requirements).to eq(
          [{
            requirement: "==0.5.1",
            file: "setup.cfg",
            groups: ["tests_require"],
            source: nil
          }]
        )
      end
    end

    describe "an extras_require dependencies" do
      subject(:dependency) { dependencies.find { |d| d.name == "flask" } }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("flask")
        expect(dependency.version).to eq("0.12.2")
        expect(dependency.requirements).to eq(
          [{
            requirement: "==0.12.2",
            file: "setup.cfg",
            groups: ["extras_require:API"],
            source: nil
          }]
        )
      end
    end

    context "without a `tests_require` key" do
      let(:setup_cfg_file_fixture_name) { "no_tests_require.cfg" }
      its(:length) { is_expected.to eq(12) }
    end

    context "with an illformed_requirement" do
      let(:setup_cfg_file_fixture_name) { "illformed_req.cfg" }

      it "raises a helpful error" do
        expect { parser.dependency_set }.
          to raise_error do |error|
            expect(error.class).
              to eq(Dependabot::DependencyFileNotEvaluatable)
            expect(error.message).
              to eq("InstallationError(\"Invalid requirement: 'psycopg2==2.6.1raven == 5.32.0'\")")
          end
      end
    end
  end
end
