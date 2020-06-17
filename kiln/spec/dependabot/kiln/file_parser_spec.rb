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
    subject(:dependencies) { parser.parse }

    context "with a version specified" do
      let(:kilnfile_fixture_name) { "Kilnfile" }

      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject { dependencies.first }
        let(:expected_requirements) do
          [{
            requirement: "~> 74.16.0",
            file: "Kilnfile",
            source: {
                type: "bosh.io"
            },
            groups: [:default]
          }]
        end

        it { is_expected.to be_a(Dependabot::Dependency) }
        its(:name) { is_expected.to eq("uaa") }
        its(:requirements) { is_expected.to eq(expected_requirements) }
          # its(:version) { is_expected.to eq("74.16.0") }
      end
    end
  end
end


