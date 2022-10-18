# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/maven/file_parser/pom_fetcher"

RSpec.describe Dependabot::Maven::FileParser::PomFetcher do
  let(:fetcher) { described_class.new(dependency_files: dependency_files) }
  let(:dependency_files) { [] }

  describe "#fetch_remote_parent_pom" do
    subject(:fetch_remote_parent_pom) { fetcher.fetch_remote_parent_pom(group_id, artifact_id, version, urls_to_try) }
    let(:group_id) { "org.springframework.boot" }
    let(:artifact_id) { "spring-boot-starter-parent" }
    let(:version) { "1.5.9.RELEASE" }
    let(:urls_to_try) { ["https://repo.maven.apache.org/maven2"] }

    before do
      stub_request(:get, "https://repo.maven.apache.org/maven2/" \
                         "org/springframework/boot/" \
                         "spring-boot-starter-parent/" \
                         "1.5.9.RELEASE/" \
                         "spring-boot-starter-parent-1.5.9.RELEASE.pom").
        to_return(status: 200, body: "<project><artifactId>spring-boot-dependencies</artifactId></project>")
    end

    context "when the parent pom is a release" do
      it "returns the parent pom" do
        expect(fetch_remote_parent_pom).to be_a(Dependabot::DependencyFile)
        expect(fetch_remote_parent_pom.name).to eq("remote_pom.xml")
        expect(fetch_remote_parent_pom.content).to include("spring-boot-dependencies")
      end
    end

    context "when the parent pom is a snapshot" do
      let(:version) { "1.5.10-SNAPSHOT" }

      before do
        stub_request(:get, "https://repo.maven.apache.org/maven2/" \
                           "org/springframework/boot/" \
                           "spring-boot-starter-parent/" \
                           "1.5.10-SNAPSHOT/" \
                           "maven-metadata.xml").
          to_return(status: 200, body: fixture("maven_central_metadata", "snapshot.xml"))
        stub_request(:get, "https://repo.maven.apache.org/maven2/" \
                           "org/springframework/boot/" \
                           "spring-boot-starter-parent/" \
                           "1.5.10-SNAPSHOT/" \
                           "spring-boot-starter-parent-14.9-20221018.091616-23.pom").
          to_return(status: 200, body: "<project><artifactId>snapshot</artifactId></project>")
      end

      it "returns the parent pom" do
        expect(fetch_remote_parent_pom).to be_a(Dependabot::DependencyFile)
        expect(fetch_remote_parent_pom.name).to eq("remote_pom.xml")
        expect(fetch_remote_parent_pom.content).to include("snapshot")
      end
    end
  end
end
