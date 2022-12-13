# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/bundler/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Bundler::MetadataFinder do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: "1.0",
      requirements:
        [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }],
      previous_requirements:
        [{ file: "Gemfile", requirement: ">= 0", groups: [], source: nil }],
      package_manager: "bundler"
    )
  end
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_name) { "business" }

  before do
    stub_request(:get, "https://example.com/status").to_return(
      status: 200,
      body: "Not GHES",
      headers: {}
    )

    stub_request(:get, "https://www.rubydoc.info/status").to_return(
      status: 200,
      body: "Not GHES",
      headers: {}
    )
  end

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    context "for a non-default rubygems source" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "1.0",
          requirements: requirements,
          package_manager: "bundler"
        )
      end
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: ">= 0",
          groups: [],
          source: source
        }]
      end
      let(:source) do
        { type: "rubygems", url: "https://SECRET_CODES@repo.fury.io/grey/" }
      end
      let(:rubygems_api_url) do
        "https://repo.fury.io/grey/api/v1/gems/business.json"
      end
      let(:rubygems_gemspec_url) do
        "https://repo.fury.io/grey/quick/Marshal.4.8/business-1.0.gemspec.rz"
      end
      let(:gemspec_response) do
        fixture("rubygems_responses", "business-1.0.0.gemspec.rz")
      end
      let(:rubygems_response) { fixture("ruby", "rubygems_response.json") }
      before do
        stub_request(:get, rubygems_api_url).
          with(headers: { "Authorization" => "Basic U0VDUkVUX0NPREVTOg==" }).
          to_return(status: 200, body: rubygems_response)
      end

      it { is_expected.to eq("https://github.com/gocardless/business") }

      context "with credentials" do
        let(:source) do
          { type: "rubygems", url: "https://gems.greysteil.com/" }
        end
        let(:credentials) do
          [
            {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => "token"
            },
            {
              "type" => "rubygems_server",
              "host" => "gems.greysteil.com.evil.com",
              "token" => "secret:token"
            },
            {
              "type" => "rubygems_server",
              "host" => "gems.greysteil.com",
              "token" => "secret:token"
            }
          ]
        end
        let(:rubygems_api_url) do
          "https://gems.greysteil.com/api/v1/gems/business.json"
        end
        before do
          stub_request(:get, rubygems_api_url).
            with(headers: { "Authorization" => "Basic c2VjcmV0OnRva2Vu" }).
            to_return(status: 200, body: rubygems_response)
        end

        it { is_expected.to eq("https://github.com/gocardless/business") }
      end

      context "with a replaces-base credential" do
        before do
          stub_request(:get, "https://gems.example.com/api/v1/gems/business.json").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems_response.json")
            )
        end

        let(:source) do
          { type: "rubygems", url: "https://gems.example.com/" }
        end
        let(:credentials) do
          [
            {
              "type" => "rubygems_server",
              "host" => "gems.greysteil.com",
              "replaces-base" => true
            }
          ]
        end

        it "prefers the source URL still" do
          expect(finder.source_url).
            to eq("https://github.com/gocardless/business")
          expect(WebMock).
            to have_requested(
              :get,
              "https://gems.example.com/api/v1/gems/business.json"
            )
          expect(WebMock).to_not have_requested(:get, rubygems_gemspec_url)
        end

        context "but with no source" do
          let(:source) { nil }

          before do
            stub_request(:get, "https://gems.greysteil.com/api/v1/gems/business.json").
              to_return(
                status: 200,
                body: fixture("ruby", "rubygems_response.json")
              )
          end

          it "uses the replaces-base URL" do
            expect(finder.source_url).
              to eq("https://github.com/gocardless/business")
            expect(WebMock).
              to have_requested(:get, "https://gems.greysteil.com/api/v1/gems/business.json")
            expect(WebMock).to_not have_requested(:get, rubygems_gemspec_url)
          end
        end
      end

      context "without a source" do
        let(:rubygems_response) do
          fixture("ruby", "rubygems_response_no_source.json")
        end

        before do
          stub_request(:get, "https://rubygems.org/api/v1/gems/business.json").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems_response.json")
            )
        end

        it "hits Rubygems to augment the details" do
          expect(finder.source_url).
            to eq("https://github.com/gocardless/business")
          expect(WebMock).
            to have_requested(
              :get,
              "https://rubygems.org/api/v1/gems/business.json"
            )
          expect(WebMock).to_not have_requested(:get, rubygems_gemspec_url)
        end

        context "but the response doesn't match" do
          before do
            stub_request(
              :get,
              "https://rubygems.org/api/v1/gems/business.json"
            ).to_return(
              status: 200,
              body: fixture("ruby", "rubygems_response.json").
                    gsub("1.5.0", "1.5.1")
            )

            stub_request(:get, rubygems_gemspec_url).
              to_return(status: 200, body: gemspec_response)
          end

          it "falls back to getting them gemspec" do
            expect(finder.source_url).
              to eq("https://github.com/gocardless/business")
            expect(WebMock).
              to have_requested(
                :get,
                "https://rubygems.org/api/v1/gems/business.json"
              )
            expect(WebMock).to have_requested(:get, rubygems_gemspec_url)
          end
        end
      end

      context "but the response is a 400" do
        before do
          stub_request(:get, rubygems_api_url).
            to_return(status: 400, body: "bad request")
          stub_request(:get, rubygems_gemspec_url).
            to_return(status: 200, body: gemspec_response)
        end

        it "falls back to getting them gemspec" do
          expect(finder.source_url).
            to eq("https://github.com/gocardless/business")
          expect(WebMock).to have_requested(:get, rubygems_gemspec_url)
        end
      end
    end

    context "for a git source" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "1.0",
          requirements: [{
            file: "Gemfile",
            requirement: ">= 0",
            groups: [],
            source: {
              type: "git",
              url: "https://github.com/my_fork/business"
            }
          }],
          package_manager: "bundler"
        )
      end

      it { is_expected.to eq("https://github.com/my_fork/business") }

      context "that doesn't match a supported source" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "1.0",
            requirements: [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://example.com/my_fork/business"
              }
            }],
            package_manager: "bundler"
          )
        end

        it { is_expected.to be_nil }
      end

      context "that is overriding a gemspec source" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: dependency_name,
            version: "1.0",
            requirements: [
              {
                file: "Gemfile",
                requirement: ">= 0",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/my_fork/business"
                }
              },
              {
                file: "example.gemspec",
                requirement: ">= 0",
                groups: [],
                source: nil
              }
            ],
            package_manager: "bundler"
          )
        end

        it { is_expected.to eq("https://github.com/my_fork/business") }
      end
    end

    context "for a default source" do
      let(:rubygems_api_url) do
        "https://rubygems.org/api/v1/gems/business.json"
      end
      let(:rubygems_response_code) { 200 }
      before do
        stub_request(:get, rubygems_api_url).
          to_return(status: rubygems_response_code, body: rubygems_response)
      end

      context "when there is a github link in the rubygems response" do
        let(:rubygems_response) { fixture("ruby", "rubygems_response.json") }

        it { is_expected.to eq("https://github.com/gocardless/business") }

        it "caches the call to rubygems" do
          2.times { source_url }
          expect(WebMock).to have_requested(:get, rubygems_api_url).once
        end

        context "that contains a . suffix (not .git)" do
          let(:rubygems_response) do
            fixture("ruby", "rubygems_response_period_github.json")
          end

          it { is_expected.to eq("https://github.com/gocardless/business.rb") }
        end

        context "that contains a # suffix" do
          let(:rubygems_response) do
            fixture("ruby", "rubygems_response_hash_github.json")
          end

          it { is_expected.to eq("https://github.com/gocardless/business") }
        end

        context "that is in the source_code_uri field, and needs a / adding" do
          let(:rubygems_response) do
            fixture("ruby", "rubygems_response_source_code_uri.json")
          end

          it { is_expected.to eq("https://github.com/gocardless/business") }

          it "stores the right directory" do
            expect(finder.send(:source).directory).to eq("gems/business-dir")
          end
        end
      end

      context "when there is a bitbucket link in the rubygems response" do
        let(:rubygems_response) do
          fixture("ruby", "rubygems_response_bitbucket.json")
        end

        it { is_expected.to eq("https://bitbucket.org/gocardless/business") }

        it "caches the call to rubygems" do
          2.times { source_url }
          expect(WebMock).to have_requested(:get, rubygems_api_url).once
        end
      end

      context "when there is a gitlab link in the rubygems response" do
        let(:rubygems_response) do
          fixture("ruby", "rubygems_response_gitlab.json")
        end

        it { is_expected.to eq("https://gitlab.com/zachdaniel/result-monad") }

        it "caches the call to rubygems" do
          2.times { source_url }
          expect(WebMock).to have_requested(:get, rubygems_api_url).once
        end
      end

      context "when there isn't a source link in the rubygems response" do
        let(:rubygems_response) do
          fixture("ruby", "rubygems_response_no_source.json")
        end

        it { is_expected.to be_nil }

        it "caches the call to rubygems" do
          2.times { source_url }
          expect(WebMock).to have_requested(:get, rubygems_api_url).once
        end
      end

      context "when the gem isn't on Rubygems" do
        let(:rubygems_response_code) { 404 }
        let(:rubygems_response) { "This rubygem could not be found." }

        it { is_expected.to be_nil }
      end
    end
  end

  describe "#homepage_url" do
    subject(:homepage_url) { finder.homepage_url }
    let(:rubygems_api_url) { "https://rubygems.org/api/v1/gems/business.json" }
    let(:rubygems_response_code) { 200 }

    before do
      stub_request(:get, rubygems_api_url).
        to_return(status: rubygems_response_code, body: rubygems_response)
    end

    context "when there is a homepage link in the rubygems response" do
      let(:rubygems_response) do
        fixture("ruby", "rubygems_response_changelog.json")
      end

      it "returns the specified homepage" do
        expect(homepage_url).to eq("http://rubyonrails.org")
      end
    end
  end

  describe "#suggested_changelog_url" do
    subject(:suggested_changelog_url) { finder.send(:suggested_changelog_url) }

    context "for a default source" do
      let(:rubygems_api_url) do
        "https://rubygems.org/api/v1/gems/business.json"
      end
      let(:rubygems_response_code) { 200 }
      before do
        stub_request(:get, rubygems_api_url).
          to_return(status: rubygems_response_code, body: rubygems_response)
      end

      context "when there is a changelog link in the rubygems response" do
        let(:rubygems_response) do
          fixture("rubygems_responses", "api_changelog_uri.json")
        end

        it "gets the URL from the changelog_uri" do
          expect(suggested_changelog_url).to eq(
            "https://github.com/rails/rails/blob/v5.2.2/" \
            "activerecord/CHANGELOG.md"
          )
        end
      end

      context "when there is no changelog link in the rubygems response" do
        let(:rubygems_response) { fixture("ruby", "rubygems_response.json") }
        it { is_expected.to be_nil }
      end
    end

    context "for a custom source" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "1.0",
          requirements: requirements,
          package_manager: "bundler"
        )
      end
      let(:requirements) do
        [{
          file: "Gemfile",
          requirement: ">= 0",
          groups: [],
          source: source
        }]
      end
      let(:source) do
        { type: "rubygems", url: "https://SECRET_CODES@repo.fury.io/grey/" }
      end
      let(:rubygems_api_url) do
        "https://repo.fury.io/grey/api/v1/gems/business.json"
      end
      let(:rubygems_gemspec_url) do
        "https://repo.fury.io/grey/quick/Marshal.4.8/business-1.0.gemspec.rz"
      end
      let(:gemspec_response) do
        fixture("rubygems_responses", "business-1.0.0.gemspec.rz")
      end

      context "but the response is a 400" do
        before do
          stub_request(:get, rubygems_api_url).
            to_return(status: 400, body: "bad request")
          stub_request(:get, rubygems_gemspec_url).
            to_return(status: 200, body: gemspec_response)
        end

        it "falls back to getting them gemspec" do
          expect(suggested_changelog_url).to be_nil
          expect(WebMock).to have_requested(:get, rubygems_gemspec_url)
        end

        context "and there is a changelog URL in the gemspec" do
          let(:gemspec_response) do
            fixture(
              "rubygems_responses", "activerecord-5.2.1.gemspec.rz"
            )
          end

          it "gets the right URL" do
            expect(suggested_changelog_url).to eq(
              "github.com/rails/rails/blob/v5.2.1/activerecord/CHANGELOG.md"
            )
          end
        end
      end
    end
  end
end
