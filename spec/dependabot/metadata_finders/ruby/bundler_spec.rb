# frozen_string_literal: true
require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/ruby/bundler"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::Ruby::Bundler do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.0",
      requirements: [{ file: "Gemfile", requirement: ">= 0", groups: [] }],
      package_manager: "bundler"
    )
  end
  subject(:finder) do
    described_class.new(dependency: dependency, github_client: github_client)
  end
  let(:github_client) { Octokit::Client.new(access_token: "token") }
  let(:dependency_name) { "business" }

  describe "#source_url" do
    subject(:source_url) { finder.source_url }
    let(:rubygems_url) { "https://rubygems.org/api/v1/gems/business.json" }
    let(:rubygems_response_code) { 200 }

    before do
      stub_request(:get, rubygems_url).
        to_return(status: rubygems_response_code, body: rubygems_response)
    end

    context "when there is a github link in the rubygems response" do
      let(:rubygems_response) { fixture("ruby", "rubygems_response.json") }

      it { is_expected.to eq("https://github.com/gocardless/business") }

      it "caches the call to rubygems" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, rubygems_url).once
      end

      context "that contains a .git suffix" do
        let(:rubygems_response) do
          fixture("ruby", "rubygems_response_period_github.json")
        end

        it { is_expected.to eq("https://github.com/gocardless/business.rb") }
      end
    end

    context "when there is a bitbucket link in the rubygems response" do
      let(:rubygems_response) do
        fixture("ruby", "rubygems_response_bitbucket.json")
      end

      it { is_expected.to eq("https://bitbucket.org/gocardless/business") }

      it "caches the call to rubygems" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, rubygems_url).once
      end
    end

    context "when there is a gitlab link in the rubygems response" do
      let(:rubygems_response) do
        fixture("ruby", "rubygems_response_gitlab.json")
      end

      it { is_expected.to eq("https://gitlab.com/zachdaniel/result-monad") }

      it "caches the call to rubygems" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, rubygems_url).once
      end
    end

    context "when there isn't a source link in the rubygems response" do
      let(:rubygems_response) do
        fixture("ruby", "rubygems_response_no_source.json")
      end

      it { is_expected.to be_nil }

      it "caches the call to rubygems" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, rubygems_url).once
      end
    end

    context "when the gem isn't on Rubygems" do
      let(:rubygems_response_code) { 404 }
      let(:rubygems_response) { "This rubygem could not be found." }

      it { is_expected.to be_nil }
    end
  end
end
