# frozen_string_literal: true

require "spec_helper"
require "dependabot/source"
require "dependabot/dependency_file"
require "dependabot/kiln/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Kiln::FileParser do
  it_behaves_like "a dependency file parser"

  let(:files) { [kilnfile, lockfile] }
  let(:kilnfile) do
    Dependabot::DependencyFile.new(name: "Kilnfile", content: kilnfile_body)
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "Kilnfile.lock", content: lockfile_body)
  end
  let(:parser) { described_class.new(dependency_files: files, source: source) }
  let(:source) do
    Dependabot::Source.new(
        provider: "github",
        repo: "releen/kiln-fixtures",
        directory: "/"
    )
  end
  let(:kilnfile_body) { fixture("kiln", kilnfile_fixture_name) }
  let(:lockfile_body) { fixture("kiln", lockfile_fixture_name) }
  let(:kilnfile_fixture_name) { "Kilnfile" }
  let(:lockfile_fixture_name) { "Kilnfile.lock" }

  describe "parse" do
    context "when the required files are not present" do
      context "without a Kilnfile" do
        it "raises a helpful error" do
          expect do
            described_class.new(dependency_files: [kilnlockfile], source: source).
                to raise_error(RuntimeError)
          end
        end
      end

      context "without a Kilnfile.lock" do
        it "raises a helpful error" do
          expect do
            described_class.new(dependency_files: [kilnfile], source: source).
                to raise_error(RuntimeError)
          end
        end
      end
    end

    context "when the required files are present" do
      subject(:dependencies) { parser.parse }

      context "with a version specified" do
        let(:kilnfile_fixture_name) { "Kilnfile" }

        its(:length) { is_expected.to eq(3) }

        describe "dependencies" do
          subject { dependencies }

          it 'has the right dependencies' do
            expect(subject).to include(Dependabot::Dependency.new(
                name: "uaa",
                requirements: [{
                                   requirement: "~74.16.0",
                                   file: "Kilnfile",
                                   source: {
                                       type: "bosh.io",
                                       remote_path: "bosh.io/uaa",
                                       sha: "somesha"
                                   },
                                   groups: [:default]
                               }],
                version: "74.15.0",
                package_manager: "kiln"
            ))

            expect(subject).to include(Dependabot::Dependency.new(
                name: "uaab",
                requirements: [{
                                   requirement: "~74.17.0",
                                   file: "Kilnfile",
                                   source: {
                                       type: "final-pcf-bosh-releases",
                                       remote_path: "uaa/uaa-74.17.0.tgz",
                                       sha: "somesha"
                                   },
                                   groups: [:default]
                               }],
                version: "74.17.0",
                package_manager: "kiln"
            ))
          end

        end
      end

      context "with a version not specified" do
        let(:kilnfile_fixture_name) { "Kilnfile" }

        its(:length) { is_expected.to eq(3) }

        describe "dependencies" do
          subject { dependencies }

          it 'still adds the dependency' do
            expect(subject).to include(Dependabot::Dependency.new(
                name: "uaac",
                requirements: [{
                                   requirement: nil,
                                   file: "Kilnfile",
                                   groups: [:default],
                                   source: {
                                       type: "compiled-releases",
                                       remote_path: "2.10/uaa/uaa-74.17.22-ubuntu-xenial-621.64.tgz",
                                       sha: "somesha"
                                   },
                               }],
                version: "74.17.22",
                package_manager: "kiln"
            ))
          end
        end
      end

      context "when the number of releases in the kilnfile differs from the lockfile" do
        let(:kilnfile_fixture_name) { "Kilnfile-with-two-releases" }

        it 'raises an error' do
          expect {subject}.to raise_error("Number of releases in Kilnfile and Kilnfile.lock does not match")
        end
      end

      context "when kilnfile has an invalid release name" do
        let(:kilnfile_fixture_name) { "Kilnfile-with-invalid-release" }

        it 'raises an error' do
          expect {subject}.to raise_error("The release 'uaa-this-is-not-a-release' does not match any release in Kilnfile.lock")
        end
      end
    end
  end
end
