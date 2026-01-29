# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/pull_request_creator/message_components/single_update_title"

RSpec.describe Dependabot::PullRequestCreator::MessageComponents::SingleUpdateTitle do
  subject(:title) { builder.build }

  let(:builder) do
    described_class.new(
      dependencies: dependencies,
      source: source,
      credentials: credentials,
      **options
    )
  end

  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
  end
  let(:credentials) { github_credentials }
  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "dummy",
      requirements:
        [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }],
      previous_requirements:
        [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
    )
  end
  let(:options) do
    {
      library: false,
      directory: "/",
      security_fix: false,
      commit_message_options: {}
    }
  end

  before do
    stub_request(:get, "https://api.github.com/repos/gocardless/bump/commits?per_page=100")
      .to_return(status: 200, body: "[]", headers: { "Content-Type" => "application/json" })
  end

  describe "#build" do
    context "when dealing with an application update" do
      it "returns the correct title" do
        expect(title).to eq("Bump business from 1.4.0 to 1.5.0")
      end

      context "with security fix" do
        let(:options) { super().merge(security_fix: true) }

        it "includes security prefix" do
          expect(title).to start_with("[Security] Bump")
        end
      end

      context "with directory specified" do
        let(:options) { super().merge(directory: "/my-dir") }

        it "includes the directory" do
          expect(title).to eq("Bump business from 1.4.0 to 1.5.0 in /my-dir")
        end
      end

      context "with root directory" do
        let(:options) { super().merge(directory: "/") }

        it "does not include the directory" do
          expect(title).to eq("Bump business from 1.4.0 to 1.5.0")
        end
      end

      context "with multiple dependencies" do
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "business2",
            version: "2.0.0",
            previous_version: "1.0.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: []
          )
        end
        let(:dependencies) { [dependency, dependency2] }

        it "lists all dependencies" do
          expect(title).to eq("Bump business and business2")
        end
      end

      context "with three dependencies" do
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "business2",
            version: "2.0.0",
            previous_version: "1.0.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: []
          )
        end
        let(:dependency3) do
          Dependabot::Dependency.new(
            name: "business3",
            version: "3.0.0",
            previous_version: "2.0.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: []
          )
        end
        let(:dependencies) { [dependency, dependency2, dependency3] }

        it "lists all dependencies with proper formatting" do
          expect(title).to eq("Bump business, business2 and business3")
        end
      end

      context "when updating a property" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "org.springframework:spring-beans",
            version: "4.3.15.RELEASE",
            previous_version: "4.3.12.RELEASE",
            package_manager: "maven",
            requirements: [{
              file: "pom.xml",
              requirement: "4.3.15.RELEASE",
              groups: [],
              source: nil,
              metadata: { property_name: "springframework.version" }
            }],
            previous_requirements: [{
              file: "pom.xml",
              requirement: "4.3.12.RELEASE",
              groups: [],
              source: nil,
              metadata: { property_name: "springframework.version" }
            }]
          )
        end

        it "uses the property name" do
          expect(title).to eq("Bump springframework.version from 4.3.12.RELEASE to 4.3.15.RELEASE")
        end
      end

      context "when updating a dependency set" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "org.springframework:spring-beans",
            version: "4.3.15.RELEASE",
            previous_version: "4.3.12.RELEASE",
            package_manager: "maven",
            requirements: [{
              file: "pom.xml",
              requirement: "4.3.15.RELEASE",
              groups: [],
              source: nil,
              metadata: { dependency_set: { group: "spring" } }
            }],
            previous_requirements: [{
              file: "pom.xml",
              requirement: "4.3.12.RELEASE",
              groups: [],
              source: nil,
              metadata: { dependency_set: { group: "spring" } }
            }]
          )
        end

        it "uses the dependency set group name" do
          expect(title).to eq("Bump spring dependency set from 4.3.12.RELEASE to 4.3.15.RELEASE")
        end
      end
    end

    context "when dealing with a library update" do
      let(:options) { super().merge(library: true) }

      it "returns the correct title" do
        expect(title).to eq("Update business requirement from ~> 1.4.0 to ~> 1.5.0")
      end

      context "with multiple dependencies" do
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "business2",
            version: "2.0.0",
            previous_version: "1.0.0",
            package_manager: "dummy",
            requirements: [{
              file: "Gemfile",
              requirement: "~> 2.0.0",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "Gemfile",
              requirement: "~> 1.0.0",
              groups: [],
              source: nil
            }]
          )
        end
        let(:dependencies) { [dependency, dependency2] }

        it "lists all dependencies" do
          expect(title).to eq("Update requirements for business and business2")
        end
      end

      context "with three dependencies" do
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "business2",
            version: "2.0.0",
            previous_version: "1.0.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: []
          )
        end
        let(:dependency3) do
          Dependabot::Dependency.new(
            name: "business3",
            version: "3.0.0",
            previous_version: "2.0.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: []
          )
        end
        let(:dependencies) { [dependency, dependency2, dependency3] }

        it "lists all dependencies" do
          expect(title).to eq("Update requirements for business, business2 and business3")
        end
      end

      context "with git dependency" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2",
            previous_version: "a1b2c3",
            package_manager: "dummy",
            requirements: [{
              file: "Gemfile",
              requirement: nil,
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/gocardless/business",
                ref: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2"
              }
            }],
            previous_requirements: [{
              file: "Gemfile",
              requirement: nil,
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/gocardless/business",
                ref: "a1b2c3"
              }
            }]
          )
        end

        it "uses ref for title" do
          expect(title).to eq("Update business requirement from a1b2c3 to cff701b3bfb182afc99a85657d7c9f3d6c1ccce2")
        end
      end
    end

    context "with prefix from commit convention" do
      before do
        stub_request(:get, "https://api.github.com/repos/gocardless/bump/commits?per_page=100")
          .to_return(
            status: 200,
            body: fixture("github", "commits_angular.json"),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "uses the commit prefix" do
        expect(title).to start_with("chore(deps):")
      end
    end
  end
end
