# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/python/file_parser/setup_file_parser"

RSpec.describe Dependabot::Python::FileParser::SetupFileParser do
  let(:parser) { described_class.new(dependency_files: files) }

  describe "#dependency_set" do
    subject(:dependencies) { parser.dependency_set.dependencies }

    let(:files) { [setup_file] }
    let(:setup_file) do
      Dependabot::DependencyFile.new(name: "setup.py", content: fixture("setup_files", "setup.py"))
    end
    let(:helper_record) do
      {
        "name" => "Some_Package",
        "version" => "2.31.0",
        "markers" => "None",
        "file" => "./setup.py",
        "requirement" => "==2.31.0",
        "requirement_type" => "extras_require:API",
        "extras" => %w(security socks)
      }
    end
    let(:helper_result) { [helper_record] }

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
        .with(hash_including(function: "parse_setup")).and_return(helper_result)
    end

    it "preserves dependency details while normalising the name and path" do
      expect(dependencies.first).to have_attributes(name: "some-package", version: "2.31.0", package_manager: "pip")
      expect(dependencies.first.metadata).to eq(extras: "security,socks")
      expect(dependencies.first.requirements).to eq(
        [{
          requirement: "==2.31.0",
          file: "setup.py",
          groups: ["extras_require:API"],
          source: nil
        }]
      )
    end

    context "with an empty result" do
      let(:helper_result) { [] }

      it "returns no dependencies" do
        expect(dependencies).to be_empty
      end
    end

    context "with unknown fields" do
      let(:helper_record) { super().merge("unknown" => { "future" => true }) }

      it "ignores them" do
        expect(dependencies.map(&:name)).to eq(["some-package"])
      end
    end

    context "without optional fields" do
      let(:helper_record) { super().except("version", "requirement", "markers") }

      it "keeps the unmarked, unpinned dependency" do
        expect(dependencies.first.version).to be_nil
        expect(dependencies.first.requirements.first.requirement).to be_nil
      end
    end

    context "with null optional fields" do
      let(:helper_record) { super().merge("version" => nil, "requirement" => nil, "markers" => nil) }

      it "keeps the unmarked, unpinned dependency" do
        expect(dependencies.first.version).to be_nil
        expect(dependencies.first.requirements.first.requirement).to be_nil
      end
    end

    ["", "None", 'python_version == "2.7"'].each do |marker|
      context "with marker #{marker.inspect}" do
        let(:helper_record) { super().merge("markers" => marker) }

        it "keeps the dependency" do
          expect(dependencies.map(&:name)).to eq(["some-package"])
        end
      end
    end

    [
      { "markers" => 'python_version <= "2.7"' },
      { "version" => "0.0.1+dependabot" }
    ].each do |excluded_fields|
      context "with excluded fields #{excluded_fields.inspect}" do
        let(:helper_record) { super().merge(excluded_fields) }

        it "omits the dependency" do
          expect(dependencies).to be_empty
        end

        context "with malformed extras" do
          let(:helper_record) { super().merge("extras" => [1]) }

          it "rejects the malformed record before filtering" do
            expect { dependencies }.to raise_error(
              Dependabot::DependencyFileNotEvaluatable,
              /parse_setup result\[0\].*extras/
            )
          end
        end
      end
    end

    context "with a wildcard version" do
      let(:helper_record) { super().merge("version" => "2.12.*", "requirement" => "==2.12.*") }

      it "preserves the requirement but clears the version" do
        expect(dependencies.first.version).to be_nil
        expect(dependencies.first.requirements.first.requirement).to eq("==2.12.*")
      end
    end

    context "with a formatted requirement" do
      let(:helper_record) { super().merge("requirement" => ">= 2.0, < 3.0") }

      it "preserves the original requirement text" do
        expect(dependencies.first.requirements.first.requirement).to eq(">= 2.0, < 3.0")
      end
    end

    context "with invalid requirement syntax" do
      let(:helper_record) { super().merge("requirement" => "not a requirement") }

      it "preserves the requirement evaluation error" do
        expect { dependencies }.to raise_error(
          Dependabot::DependencyFileNotEvaluatable,
          'Illformed requirement ["not a requirement"]'
        )
      end
    end

    [nil, {}, "invalid", 1, false].each do |value|
      context "with #{value.inspect} as the result" do
        let(:helper_result) { value }

        it "reports a malformed result without retrying" do
          expect { dependencies }.to raise_error(
            Dependabot::DependencyFileNotEvaluatable,
            "parse_setup result must be an array"
          )
          expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess).once
        end
      end
    end

    [nil, [], "invalid", 1, false].each do |value|
      context "with #{value.inspect} as a record" do
        let(:helper_result) { [helper_record, value] }

        it "identifies the malformed record" do
          expect { dependencies }.to raise_error(
            Dependabot::DependencyFileNotEvaluatable,
            /parse_setup result\[1\].*must be an object/
          )
        end
      end
    end

    %w(name file requirement_type extras).each do |field|
      context "without #{field}" do
        let(:helper_record) { super().except(field) }

        it "identifies the missing field" do
          expect { dependencies }.to raise_error(
            Dependabot::DependencyFileNotEvaluatable,
            /parse_setup result\[0\].*#{field}/
          )
        end
      end
    end

    [
      ["name", 1],
      ["file", false],
      ["requirement_type", nil],
      ["requirement_type", []],
      ["version", 1],
      ["markers", false],
      ["requirement", []],
      ["extras", nil],
      %w(extras not-an-extra-list),
      ["extras", ["security", 1]]
    ].each do |field, value|
      context "with #{field} set to #{value.inspect}" do
        let(:helper_result) { [helper_record, helper_record.merge(field => value)] }

        it "identifies the field without echoing the helper response" do
          expect { dependencies }.to raise_error(
            Dependabot::DependencyFileNotEvaluatable,
            /parse_setup result\[1\].*#{field}/
          ) do |error|
            expect(error.message).not_to include("not-an-extra-list")
          end
        end
      end
    end

    context "with a non-string key" do
      let(:helper_record) { super().merge(unknown: "value") }

      it "identifies the record's key type" do
        expect { dependencies }.to raise_error(
          Dependabot::DependencyFileNotEvaluatable,
          /parse_setup result\[0\].*keys must be strings/
        )
      end
    end

    context "when the helper call raises an unrelated type error" do
      before do
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
          .with(hash_including(function: "parse_setup")).and_raise(TypeError, "unexpected helper type error")
      end

      it "does not relabel the exception" do
        expect { dependencies }.to raise_error(TypeError, "unexpected helper type error")
        expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess).once
      end
    end

    context "when the primary helper fails" do
      let(:helper_error) do
        Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: "Unexpected helper failure", error_context: {})
      end
      let(:retry_error) { nil }

      before do
        first_call = true
        allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
          .with(hash_including(function: "parse_setup")) do
            if first_call
              first_call = false
              raise helper_error
            end

            raise retry_error if retry_error

            helper_result
          end
      end

      it "decodes the sanitised retry result" do
        expect(dependencies.first).to have_attributes(name: "some-package", version: "2.31.0")
        expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess).twice
      end

      context "with an installation error" do
        let(:helper_error) do
          Dependabot::SharedHelpers::HelperSubprocessFailed.new(
            message: "InstallationError: invalid requirement",
            error_context: {}
          )
        end

        it "preserves the error without retrying" do
          expect { dependencies }.to raise_error(Dependabot::DependencyFileNotEvaluatable, helper_error.message)
          expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess).once
        end
      end

      context "without a setup.py" do
        let(:files) { [Dependabot::DependencyFile.new(name: "setup.cfg", content: "[options]\n")] }

        it "returns no dependencies without retrying" do
          expect(dependencies).to be_empty
          expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess).once
        end
      end

      context "with a malformed retry result" do
        let(:helper_record) { super().merge("extras" => [1]) }

        it "reports the malformed result rather than swallowing the error" do
          expect { dependencies }.to raise_error(
            Dependabot::DependencyFileNotEvaluatable,
            /parse_setup result\[0\].*extras/
          )
          expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess).twice
        end
      end

      ["Unexpected helper failure", "InstallationError: invalid requirement"].each do |message|
        context "when the retry fails with #{message}" do
          let(:retry_error) do
            Dependabot::SharedHelpers::HelperSubprocessFailed.new(message: message, error_context: {})
          end

          it "preserves the empty-result fallback" do
            expect(dependencies).to be_empty
            expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess).twice
          end
        end
      end
    end
  end

  describe "for setup.py" do
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

        it "parses the sanitised file with the real helper" do
          allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess).and_call_original

          expect(dependencies.length).to eq(12)
          expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess).twice
        end
      end

      context "with an illformed_requirement" do
        let(:setup_file_fixture_name) { "illformed_req.py" }

        it "raises a helpful error" do
          pending "this error is not raised in pip >= 25, so we are skipping this test"
          expect { parser.dependency_set }
            .to raise_error do |error|
              expect(error.class)
                .to eq(Dependabot::DependencyFileNotEvaluatable)
              expect(error.message)
                .to eq('Illformed requirement ["==2.6.1raven==5.32.0"]')
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
            expect(dependencies.map(&:name)).not_to include("acme")
          end
        end
      end
    end
  end

  describe "for setup.cfg" do
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
              groups: ["extras_require:api"],
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
          expect { parser.dependency_set }
            .to raise_error do |error|
              expect(error.class)
                .to eq(Dependabot::DependencyFileNotEvaluatable)
              expect(error.message)
                .to include("InstallationError(\"Invalid requirement: 'psycopg2==2.6.1raven == 5.32.0'")
            end
        end
      end

      context "with comments in the setup.cfg file" do
        subject(:dependency) { dependencies.find { |d| d.name == "boto3" } }

        let(:setup_cfg_file_fixture_name) { "with_comments.cfg" }

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
    end
  end
end
