# frozen_string_literal: true

require "spec_helper"
require "dependabot/lein/file_fetcher"
require "dependabot/lein/file_parser"
require_common_spec "file_parsers/shared_examples_for_file_parsers"

RSpec.describe Dependabot::Lein::FileParser, :vcr do
  it_behaves_like "a dependency file parser"

  let(:credentials) { github_credentials }
  let(:files) { file_fetcher_instance.files }
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "dakrone/clj-http",
      directory: "/"
    )
  end
  let(:file_fetcher_instance) do
    Dependabot::Lein::FileFetcher.new(source: source, credentials: credentials)
  end

  let(:file_parser_instance) do
    described_class.new(dependency_files: files, source: source)
  end

  describe "#parse" do
    subject(:dependencies) { file_parser_instance.parse }

    it "has nine dependencies" do
      expect(dependencies.count).to eq(9)
    end

    describe "the first dependency" do
      subject(:dependency) { dependencies.first }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("org.apache.httpcomponents:httpcore")
        expect(dependency.version).to eq("4.4.13")
        expect(dependency.package_manager).to eq("lein")
        expect(dependency.requirements).to eq(
          [{
            requirement: "4.4.13",
            file: "pom.xml",
            groups: [],
            source: nil,
            metadata: { packaging_type: "jar" }
          }]
        )
      end
    end

    describe "the second dependency" do
      subject(:dependency) { dependencies[1] }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("org.apache.httpcomponents:httpclient")
        expect(dependency.version).to eq("4.5.13")
        expect(dependency.package_manager).to eq("lein")
        expect(dependency.requirements).to eq(
          [{
            requirement: "4.5.13",
            file: "pom.xml",
            groups: [],
            source: nil,
            metadata: { packaging_type: "jar" }
          }]
        )
      end
    end

    describe "the last dependency" do
      subject(:dependency) { dependencies[8] }

      it "has the right details" do
        expect(dependency).to be_a(Dependabot::Dependency)
        expect(dependency.name).to eq("potemkin:potemkin")
        expect(dependency.version).to eq("0.4.5")
        expect(dependency.package_manager).to eq("lein")
        expect(dependency.requirements).to eq(
          [{
            requirement: "0.4.5",
            file: "pom.xml",
            groups: [],
            source: nil,
            metadata: { packaging_type: "jar" }
          }]
        )
      end
    end
  end
end
