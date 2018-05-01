# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/java/gradle"
require_relative "../shared_examples_for_file_parsers"

RSpec.describe Dependabot::FileParsers::Java::Gradle do
  it_behaves_like "a dependency file parser"

  let(:files) { [buildfile] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("java", "buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "basic_build.gradle" }
  let(:parser) { described_class.new(dependency_files: files, repo: "org/nm") }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    context "for top-level dependencies" do
      its(:length) { is_expected.to eq(16) }

      describe "the first dependency" do
        subject(:dependency) { dependencies.first }

        it "has the right details" do
          expect(dependency).to be_a(Dependabot::Dependency)
          expect(dependency.name).to eq("co.aikar:acf-paper")
          expect(dependency.version).to eq("0.5.0-SNAPSHOT")
          expect(dependency.requirements).to eq(
            [{
              requirement: "0.5.0-SNAPSHOT",
              file: "build.gradle",
              groups: [],
              source: nil
            }]
          )
        end
      end
    end
  end
end
