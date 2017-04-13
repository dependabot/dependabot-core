# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"

RSpec.describe Bump::Dependency do
  subject(:dependency) do
    described_class.new(name: name,
                        version: version,
                        previous_version: previous_version)
  end
  let(:name) { "business" }
  let(:version) { "1.4.0" }
  let(:previous_version) { nil }

  describe "#github_repo" do
    subject { dependency.github_repo }

    context "with no language" do
      it { is_expected.to be_nil }
    end

    context "for a Ruby dependency" do
      subject(:dependency) do
        described_class.new(name: name, version: version, language: "ruby")
      end

      it "delegates to a Bump::DependencySourceCodeFinder" do
        expect_any_instance_of(Bump::DependencySourceCodeFinders::Ruby).
          to receive(:github_repo).
          and_return("gocardless/business")
        dependency.github_repo
      end
    end
  end

  describe "#github_repo_url" do
    subject { dependency.github_repo_url }

    context "with a github repo" do
      before do
        allow(dependency).
          to receive(:github_repo).
          and_return("gocardless/business")
      end

      it { is_expected.to eq("https://github.com/gocardless/business") }
    end

    context "without a github repo" do
      before { allow(dependency).to receive(:github_repo).and_return(nil) }
      it { is_expected.to be_nil }
    end
  end

  context "#github_compare_url" do
    subject { dependency.github_compare_url }

    context "with a github repo and old/new tags" do
      let(:previous_version) { "1.3.0" }

      before do
        allow(dependency).
          to receive(:github_repo).
          and_return("gocardless/business")

        stub_request(:get,
                     "https://api.github.com/repos/gocardless/business/tags").
          to_return(status: 200,
                    body: fixture("github", "business_tags.json"),
                    headers: { "Content-Type" => "application/json" })
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/"\
                          "compare/v1.3.0...v1.4.0")
      end
    end

    context "with a github repo and only a new tag" do
      before do
        allow(dependency).
          to receive(:github_repo).
          and_return("gocardless/business")

        stub_request(:get,
                     "https://api.github.com/repos/gocardless/business/tags").
          to_return(status: 200,
                    body: fixture("github", "business_tags.json"),
                    headers: { "Content-Type" => "application/json" })
      end

      it do
        is_expected.
          to eq("https://github.com/gocardless/business/commits/v1.4.0")
      end
    end

    context "with a github repo and no tags found" do
      before do
        allow(dependency).
          to receive(:github_repo).
          and_return("gocardless/business")

        stub_request(:get,
                     "https://api.github.com/repos/gocardless/business/tags").
          to_return(status: 200,
                    body: "[]",
                    headers: { "Content-Type" => "application/json" })
      end

      it do
        is_expected.to eq("https://github.com/gocardless/business/commits")
      end
    end

    context "without a github repo" do
      before { allow(dependency).to receive(:github_repo).and_return(nil) }
      it { is_expected.to be_nil }
    end
  end

  describe "#changelog_url" do
    subject { dependency.changelog_url }

    context "with a github repo" do
      before do
        allow(dependency).
          to receive(:github_repo).
          and_return("gocardless/business")
      end

      let(:github_url) do
        "https://api.github.com/repos/gocardless/business/contents/"
      end

      let(:github_status) { 200 }

      before do
        stub_request(:get, github_url).
          to_return(status: github_status,
                    body: github_response,
                    headers: { "Content-Type" => "application/json" })
      end

      context "with a changelog" do
        let(:github_response) { fixture("github", "business_files.json") }

        it "gets the right URL" do
          expect(dependency.changelog_url).
            to eq(
              "https://github.com/gocardless/business/blob/master/CHANGELOG.md"
            )
        end

        it "caches the call to github" do
          2.times { dependency.changelog_url }
          expect(WebMock).to have_requested(:get, github_url).once
        end
      end

      context "without a changelog" do
        let(:github_response) do
          fixture("github", "business_files_no_changelog.json")
        end

        it { is_expected.to be_nil }

        it "caches the call to github" do
          2.times { dependency.changelog_url }
          expect(WebMock).to have_requested(:get, github_url).once
        end
      end

      context "when the github_repo doesn't exists" do
        let(:github_response) { fixture("github", "not_found.json") }
        let(:github_status) { 404 }

        it { is_expected.to be_nil }
      end
    end

    context "without a github repo" do
      before { allow(dependency).to receive(:github_repo).and_return(nil) }
      it { is_expected.to be_nil }
    end
  end
end
