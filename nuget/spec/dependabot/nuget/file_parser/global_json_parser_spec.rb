# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/nuget/file_parser/global_json_parser"

RSpec.describe Dependabot::Nuget::FileParser::GlobalJsonParser do
  let(:file) do
    Dependabot::DependencyFile.new(name: "global.json", content: file_body)
  end
  let(:file_body) { fixture("global_jsons", "global.json") }
  let(:parser) { described_class.new(global_json: file) }

  describe "dependency_set" do
    subject(:dependency_set) { parser.dependency_set }

    it { is_expected.to be_a(Dependabot::FileParsers::Base::DependencySet) }

    describe "the dependencies" do
      subject(:dependencies) { dependency_set.dependencies }

      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("Microsoft.Build.Traversal")
          expect(dependency.version).to eq("1.0.45")
          expect(dependency.requirements).to eq(
            [{
              requirement: "1.0.45",
              file: "global.json",
              groups: [],
              source: nil
            }]
          )
        end
      end

      context "with bad JSON" do
        let(:file_body) { fixture("global_jsons", "invalid_json.json") }

        it "raises a Dependabot::DependencyFileNotParseable error" do
          expect { parser.dependency_set }.
            to raise_error(Dependabot::DependencyFileNotParseable) do |error|
              expect(error.file_name).to eq("global.json")
            end
        end
      end
    end
  end
end
