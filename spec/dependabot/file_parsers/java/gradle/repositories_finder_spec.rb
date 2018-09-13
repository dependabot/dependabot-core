# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/file_parsers/java/gradle/repositories_finder"

RSpec.describe Dependabot::FileParsers::Java::Gradle::RepositoriesFinder do
  let(:finder) do
    described_class.new(
      dependency_files: dependency_files,
      target_dependency_file: target_dependency_file
    )
  end

  let(:dependency_files) { [buildfile] }
  let(:target_dependency_file) { buildfile }
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

      context "some of which are for subprojects" do
        let(:buildfile_fixture_name) { "subproject_repos.gradle" }

        it "doesn't include the subproject declarations" do
          expect(repository_urls).
            to match_array(%w(https://jcenter.bintray.com))
        end

        context "and this is a subproject" do
          let(:dependency_files) { [buildfile, subproject] }
          let(:target_dependency_file) { subproject }
          let(:subproject) do
            Dependabot::DependencyFile.new(
              name: "myapp/build.gradle",
              content: fixture("java", "buildfiles", "basic_build.gradle")
            )
          end

          it "includes the subproject declarations, too" do
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

      context "that eval code within them" do
        let(:buildfile_fixture_name) { "eval_repo_build.gradle" }

        it "ignores the repo that needs evaling" do
          expect(repository_urls).to match_array(
            %w(
              https://jcenter.bintray.com
              https://maven.google.com
            )
          )
        end
      end

      context "that get URLs from a variable" do
        let(:buildfile_fixture_name) { "variable_repos_build.gradle" }

        pending "includes the additional declarations" do
          expect(repository_urls).to match_array(
            %w(
              https://jcenter.bintray.com
              https://dl.bintray.com/magnusja/maven
              https://maven.google.com
              https://kotlin.bintray.com/kotlinx
              https://kotlin.bintray.com/ktor
              https://kotlin.bintray.com/kotlin-dev/
            )
          )
        end
      end
    end
  end
end
