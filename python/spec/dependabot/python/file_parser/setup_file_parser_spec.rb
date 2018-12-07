# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/python/file_parser/setup_file_parser"

RSpec.describe Dependabot::Python::FileParser::SetupFileParser do
  let(:parser) { described_class.new(dependency_files: files) }

  let(:files) { [setup_file] }
  let(:setup_file) do
    Dependabot::DependencyFile.new(
      name: "setup.py",
      content: setup_file_body
    )
  end
  let(:setup_file_body) do
    fixture("setup_files", setup_file_fixture_name)
  end
  let(:setup_file_fixture_name) { "setup.py" }

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
            file: "setup.py",
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
            file: "setup.py",
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
            file: "setup.py",
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
            file: "setup.py",
            groups: ["extras_require:API"],
            source: nil
          }]
        )
      end
    end

    context "without a `tests_require` key" do
      let(:setup_file_fixture_name) { "no_tests_require.py" }
      its(:length) { is_expected.to eq(12) }
    end

    context "with a `print` statement" do
      let(:setup_file_fixture_name) { "with_print.py" }
      its(:length) { is_expected.to eq(14) }
    end

    context "with an import statements that can't be handled" do
      let(:setup_file_fixture_name) { "impossible_imports.py" }
      its(:length) { is_expected.to eq(12) }
    end

    context "with an illformed_requirement" do
      let(:setup_file_fixture_name) { "illformed_req.py" }

      it "raises a helpful error" do
        expect { parser.dependency_set }.
          to raise_error do |error|
            expect(error.class).
              to eq(Dependabot::DependencyFileNotEvaluatable)
            expect(error.message).
              to eq('Illformed requirement ["==2.6.1raven==5.32.0"]')
          end
      end
    end

    context "with an `open` statement" do
      let(:setup_file_fixture_name) { "with_open.py" }
      its(:length) { is_expected.to eq(14) }
    end

    context "with the setup.py from requests" do
      let(:setup_file_fixture_name) { "requests_setup.py" }
      its(:length) { is_expected.to eq(13) }
    end

    context "with an import of a config file" do
      let(:setup_file_fixture_name) { "imports_version.py" }
      its(:length) { is_expected.to eq(14) }

      context "with a inserted version" do
        let(:setup_file_fixture_name) { "imports_version_for_dep.py" }

        it "excludes the dependency importing a version" do
          expect(dependencies.count).to eq(14)
          expect(dependencies.map(&:name)).to_not include("acme")
        end
      end
    end
  end
end
