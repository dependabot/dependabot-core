# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator/message_components/single_update_title"

RSpec.describe Dependabot::PullRequestCreator::MessageComponents::SingleUpdateTitle do
  subject(:title_builder) do
    described_class.new(
      dependencies: dependencies,
      source: source,
      credentials: credentials,
      files: files,
      vulnerabilities_fixed: vulnerabilities_fixed,
      commit_message_options: commit_message_options,
      dependency_group: nil
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

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:watched_repo_url) { "https://api.github.com/repos/#{source.repo}" }

  describe "#base_title" do
    subject(:base_title) { title_builder.base_title }

    context "with a single dependency update" do
      before do
        stub_request(:get, watched_repo_url + "/commits?per_page=100")
          .to_return(status: 200, body: "[]", headers: json_header)
      end

      it { is_expected.to eq("bump business from 1.4.0 to 1.5.0") }

      context "with a directory specified" do
        let(:gemfile) do
          Dependabot::DependencyFile.new(
            name: "Gemfile",
            content: "source 'https://rubygems.org'\ngem 'business'",
            directory: "my-dir"
          )
        end

        it "includes the directory" do
          expect(base_title).to eq("bump business from 1.4.0 to 1.5.0 in /my-dir")
        end
      end

      context "with a library dependency" do
        let(:gemfile) do
          Dependabot::DependencyFile.new(
            name: "business.gemspec",
            content: "Gem::Specification.new { |s| s.add_dependency('dep') }"
          )
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: nil,
            previous_version: nil,
            package_manager: "bundler",
            requirements: [{ file: "business.gemspec", requirement: "~> 1.5.0", groups: [], source: nil }],
            previous_requirements: [{ file: "business.gemspec", requirement: "~> 1.4.0", groups: [], source: nil }]
          )
        end

        it "uses update terminology" do
          expect(base_title).to eq("update business requirement from ~> 1.4.0 to ~> 1.5.0")
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

      before do
        stub_request(:get, watched_repo_url + "/commits?per_page=100")
          .to_return(status: 200, body: "[]", headers: json_header)
      end

      it { is_expected.to eq("bump business and business2") }

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

        it { is_expected.to eq("bump business, business2 and business3") }
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
      expect(title).to eq("Bump business from 1.4.0 to 1.5.0")
    end

    context "with security vulnerability" do
      let(:vulnerabilities_fixed) { { "business" => [{}] } }

      it "includes security prefix" do
        expect(title).to start_with("[Security]")
      end
    end
  end
end
