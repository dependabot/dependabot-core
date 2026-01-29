# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/dependency_group"
require "dependabot/pull_request_creator/message_components/group_update_title"

RSpec.describe Dependabot::PullRequestCreator::MessageComponents::GroupUpdateTitle do
  subject(:title_builder) do
    described_class.new(
      dependencies: dependencies,
      source: source,
      credentials: credentials,
      files: files,
      vulnerabilities_fixed: vulnerabilities_fixed,
      commit_message_options: commit_message_options,
      dependency_group: dependency_group
    )
  end

  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
  end
  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "bundler",
      requirements: [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }],
      previous_requirements: [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
    )
  end
  let(:files) { [gemfile] }
  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: "source 'https://rubygems.org'\ngem 'business'"
    )
  end
  let(:credentials) { [] }
  let(:vulnerabilities_fixed) { {} }
  let(:commit_message_options) { {} }
  let(:dependency_group) do
    Dependabot::DependencyGroup.new(name: "all-the-things", rules: { patterns: ["*"] })
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:watched_repo_url) { "https://api.github.com/repos/#{source.repo}" }

  describe "#base_title" do
    subject(:base_title) { title_builder.base_title }

    before do
      stub_request(:get, watched_repo_url + "/commits?per_page=100")
        .to_return(status: 200, body: "[]", headers: json_header)
    end

    context "with a single dependency in the group" do
      it { is_expected.to eq("bump business from 1.4.0 to 1.5.0 in the all-the-things group") }

      context "with a directory specified" do
        let(:gemfile) do
          Dependabot::DependencyFile.new(
            name: "Gemfile",
            content: "source 'https://rubygems.org'\ngem 'business'",
            directory: "my-dir"
          )
        end

        it "does not include directory in single dependency group title" do
          expect(base_title).to eq("bump business from 1.4.0 to 1.5.0 in /my-dir in the all-the-things group")
        end
      end
    end

    context "with multiple dependencies" do
      let(:dependency2) do
        Dependabot::Dependency.new(
          name: "business2",
          version: "1.5.0",
          previous_version: "1.4.0",
          package_manager: "bundler",
          requirements: [],
          previous_requirements: []
        )
      end
      let(:dependencies) { [dependency, dependency2] }

      it { is_expected.to eq("bump the all-the-things group with 2 updates") }

      context "with a directory specified" do
        let(:gemfile) do
          Dependabot::DependencyFile.new(
            name: "Gemfile",
            content: "source 'https://rubygems.org'\ngem 'business'",
            directory: "my-dir"
          )
        end

        it "includes the directory" do
          expect(base_title).to eq("bump the all-the-things group in /my-dir with 2 updates")
        end
      end

      context "with three dependencies" do
        let(:dependency3) do
          Dependabot::Dependency.new(
            name: "business3",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "bundler",
            requirements: [],
            previous_requirements: []
          )
        end
        let(:dependencies) { [dependency, dependency2, dependency3] }

        it { is_expected.to eq("bump the all-the-things group with 3 updates") }
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
      let(:dependency_group) do
        Dependabot::DependencyGroup.new(name: "go_modules", rules: { patterns: ["*"] })
      end
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          version: "1.5.0",
          previous_version: "1.4.0",
          package_manager: "bundler",
          requirements: [],
          previous_requirements: [],
          metadata: { directory: "/foo" }
        )
      end

      context "with a single dependency" do
        it "includes directory count" do
          expect(base_title).to eq("bump business from 1.4.0 to 1.5.0 in the go_modules group across 1 directory")
        end
      end

      context "with multiple dependencies across directories" do
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "business2",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "bundler",
            requirements: [],
            previous_requirements: [],
            metadata: { directory: "/bar" }
          )
        end
        let(:dependencies) { [dependency, dependency2] }

        it "includes directory count with plural" do
          expect(base_title).to eq("bump the go_modules group across 2 directories with 2 updates")
        end
      end
    end
  end

  describe "#build" do
    subject(:title) { title_builder.build }

    before do
      stub_request(:get, watched_repo_url + "/commits?per_page=100")
        .to_return(status: 200, body: "[]", headers: json_header)
    end

    it "returns the complete title with capitalization" do
      expect(title).to eq("Bump business from 1.4.0 to 1.5.0 in the all-the-things group")
    end

    context "with security vulnerability" do
      let(:vulnerabilities_fixed) { { "business" => [{}] } }

      it "includes security prefix" do
        expect(title).to start_with("[Security]")
      end
    end
  end
end
