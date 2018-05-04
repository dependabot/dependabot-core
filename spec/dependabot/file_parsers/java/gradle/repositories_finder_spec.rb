# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/java/gradle/repositories_finder"

RSpec.describe Dependabot::FileParsers::Java::Gradle::RepositoriesFinder do
  let(:finder) { described_class.new(dependency_files: dependency_files) }

  let(:dependency_files) { [buildfile] }
  let(:buildfile) do
    Dependabot::DependencyFile.new(
      name: "build.gradle",
      content: fixture("java", "buildfiles", buildfile_fixture_name)
    )
  end
  let(:buildfile_fixture_name) { "basic_build.gradle" }

  describe "#repository_urls" do
    subject(:repository_urls) { finder.repository_urls }

    context "when there are no repository declarations" do
      let(:buildfile_fixture_name) { "basic_build.gradle" }
      it { is_expected.to eq(["https://repo.maven.apache.org/maven2"]) }
    end

    context "when there are repository declarations" do
      let(:buildfile_fixture_name) { "custom_repos_build.gradle" }

      it "includes the additional declarations" do
        expect(repository_urls).to match_array(
          %w(
            https://jcenter.bintray.com
            https://dl.bintray.com/magnusja/maven
            https://maven.google.com
          )
        )
      end
    end
  end
end
