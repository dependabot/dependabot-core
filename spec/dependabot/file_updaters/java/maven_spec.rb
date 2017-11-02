# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/file_updaters/java/maven"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Java::Maven do
  it_behaves_like "a dependency file updater"

  let(:updater) do
    described_class.new(
      dependency_files: [pom],
      dependency: dependency,
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end
  let(:pom) do
    Dependabot::DependencyFile.new(
      content: pom_body,
      name: "pom.xml"
    )
  end
  let(:pom_body) do
    fixture("java", "poms", "basic_pom.xml")
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "org.apache.httpcomponents/httpclient",
      version: "4.6.1",
      requirements: [
        {
          file: "pom.xml",
          requirement: "4.6.1",
          groups: [],
          source: nil
        }
      ],
      previous_requirements: [
        {
          file: "pom.xml",
          requirement: "4.5.3",
          groups: [],
          source: nil
        }
      ],
      package_manager: "maven"
    )
  end

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(1) }

    describe "the updated pom file" do
      subject(:updated_pom_file) do
        updated_files.find { |f| f.name == "pom.xml" }
      end

      its(:content) { is_expected.to include "<version>4.6.1</version>" }
      its(:content) { is_expected.to include "<version>23.3-jre</version>" }
    end
  end
end
