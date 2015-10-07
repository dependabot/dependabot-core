require "spec_helper"
require "./app/dependency"

RSpec.describe Dependency do
  subject(:dependency) { described_class.new(name: name, version: version) }
  let(:name) { "business" }
  let(:version) { "1.4.0" }

  describe "#github_repo" do
    subject { dependency.github_repo }
    let(:rubygems_url) { "https://rubygems.org/api/v1/gems/business.yaml" }

    before do
      stub_request(:get, rubygems_url).
        to_return(status: 200, body: rubygems_response)
    end

    context "when there is a github link in the rubygems response" do
      let(:rubygems_response) { fixture("rubygems_response.yaml") }

      it { is_expected.to eq("gocardless/business") }

      it "caches the call to rubygems" do
        2.times { dependency.github_repo }
        expect(WebMock).to have_requested(:get, rubygems_url).once
      end
    end

    context "when there isn't github link in the rubygems response" do
      let(:rubygems_response) { fixture("rubygems_response_no_github.yaml") }

      it { is_expected.to be_nil }

      it "caches the call to rubygems" do
        2.times { dependency.github_repo }
        expect(WebMock).to have_requested(:get, rubygems_url).once
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
        stub_request(:get, "#{github_url}").
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
