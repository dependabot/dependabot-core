# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_group"
require "dependabot/pull_request_creator/message_components/group_update_title"

RSpec.describe Dependabot::PullRequestCreator::MessageComponents::GroupUpdateTitle do
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
      requirements: [],
      previous_requirements: []
    )
  end
  let(:dependency_group) do
    Dependabot::DependencyGroup.new(name: "all-the-things", rules: { patterns: ["*"] })
  end
  let(:options) do
    {
      dependency_group: dependency_group,
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
    context "with a single dependency" do
      it "includes the dependency name and group" do
        expect(title).to eq("Bump business from 1.4.0 to 1.5.0 in the all-the-things group")
      end

      context "with security fix" do
        let(:options) { super().merge(security_fix: true) }

        it "includes security prefix" do
          expect(title).to start_with("[Security] Bump")
        end
      end

      context "with directory specified" do
        let(:options) { super().merge(directory: "/my-dir") }

        it "does not include directory for single dependency" do
          # Single dependency titles don't include directory in group updates
          expect(title).to eq("Bump business from 1.4.0 to 1.5.0 in the all-the-things group")
        end
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

      it "shows the update count" do
        expect(title).to eq("Bump the all-the-things group with 2 updates")
      end

      context "with directory specified" do
        let(:options) { super().merge(directory: "/my-dir") }

        it "includes the directory" do
          expect(title).to eq("Bump the all-the-things group in /my-dir with 2 updates")
        end
      end

      context "with three dependencies" do
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

        it "shows the correct update count" do
          expect(title).to eq("Bump the all-the-things group with 3 updates")
        end
      end

      context "with dependencies with the same name" do
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.6.0",
            previous_version: "1.5.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: []
          )
        end
        let(:dependencies) { [dependency, dependency2] }

        it "counts unique dependencies" do
          expect(title).to eq("Bump the all-the-things group with 1 update")
        end
      end
    end

    context "with multi-directory source" do
      let(:source) do
        Dependabot::Source.new(
          provider: "github",
          repo: "gocardless/bump",
          directories: ["/foo", "/bar"]
        )
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "1.5.0",
          previous_version: "1.4.0",
          package_manager: "dummy",
          requirements: [],
          previous_requirements: [],
          metadata: { directory: "/foo" }
        )
      end

      context "with a single dependency" do
        it "shows directory count" do
          expect(title).to eq("Bump business from 1.4.0 to 1.5.0 in the all-the-things group across 1 directory")
        end
      end

      context "with multiple dependencies in different directories" do
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "business2",
            version: "2.0.0",
            previous_version: "1.0.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: [],
            metadata: { directory: "/bar" }
          )
        end
        let(:dependencies) { [dependency, dependency2] }

        it "shows directory count with plural" do
          expect(title).to eq("Bump the all-the-things group across 2 directories with 2 updates")
        end
      end

      context "with multiple dependencies in the same directory" do
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "business2",
            version: "2.0.0",
            previous_version: "1.0.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: [],
            metadata: { directory: "/foo" }
          )
        end
        let(:dependencies) { [dependency, dependency2] }

        it "shows single directory" do
          expect(title).to eq("Bump the all-the-things group across 1 directory with 2 updates")
        end
      end
    end

    context "with different group names" do
      let(:dependency_group) do
        Dependabot::DependencyGroup.new(name: "production-dependencies", rules: { patterns: ["*"] })
      end

      it "uses the correct group name" do
        expect(title).to eq("Bump business from 1.4.0 to 1.5.0 in the production-dependencies group")
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
