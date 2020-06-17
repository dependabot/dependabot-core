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

      its(:length) { is_expected.to eq(2) }

      describe "two dependencies" do
        subject { dependencies }
        let(:expected_requirements) do
          [[{
                requirement: "~> 74.16.0",
                file: "Kilnfile",
                source: {
                    type: "bosh.io"
                },
                groups: [:default]
            }],
           [{
                requirement: "~> 74.17.0",
                file: "Kilnfile",
                source: {
                    type: "bosh.io"
                },
                groups: [:default]
            }]]
        end

        it 'is the right type' do
          expect(subject[0]).to be_a(Dependabot::Dependency)
          expect(subject[1]).to be_a(Dependabot::Dependency)
        end

        it 'has the right name' do
          expect(subject[0].name).to eq("uaa")
          expect(subject[1].name).to eq("uaab")
        end

        it 'has the right version' do
          expect(subject[0].version).to eq("74.16.0")
          expect(subject[1].version).to eq("74.17.0")
        end

        it 'has the right requirements' do
          expect(subject[0].requirements).to eq(expected_requirements[0])
          expect(subject[1].requirements).to eq(expected_requirements[1])
        end

      end
    end
  end
end


