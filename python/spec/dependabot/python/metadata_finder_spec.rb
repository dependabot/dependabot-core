# typed: false
# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/python/metadata_finder"
require_common_spec "metadata_finders/shared_examples_for_metadata_finders"

RSpec.describe Dependabot::Python::MetadataFinder do
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end

  let(:version) { "1.0" }
  let(:dependency_name) { "luigi" }
  let(:credentials) do
    [Dependabot::Credential.new({
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    })]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: [{
        file: "requirements.txt",
        requirement: "==#{version}",
        groups: [],
        source: nil
      }],
      package_manager: "pip"
    )
  end

  before do
    stub_request(:get, "https://example.com/status").to_return(
      status: 200,
      body: "Not GHES",
      headers: {}
    )
    stub_request(:get, "https://initd.org/status").to_return(status: 404)
    stub_request(:get, "https://pypi.org/status").to_return(status: 404)
  end

  it_behaves_like "a dependency metadata finder"

  describe "#source_url" do
    subject(:source_url) { finder.source_url }

    let(:pypi_url) { "https://pypi.org/pypi/#{dependency_name}/json" }

    before do
      stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
    end

    context "when there is a github link in the pypi response" do
      let(:pypi_response) { fixture("pypi", "pypi_response.json") }

      it { is_expected.to eq("https://github.com/spotify/luigi") }

      it "caches the call to pypi" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, pypi_url).once
      end
    end

    context "with a private index" do
      let(:credentials) do
        [Dependabot::Credential.new({
          "type" => "git_source",
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }), Dependabot::Credential.new({
          "type" => "python_index",
          "index-url" => "https://username:password@pypi.posrip.com/pypi/"
        })]
      end
      let(:pypi_response) { fixture("pypi", "pypi_response.json") }

      before do
        private_url = "https://pypi.posrip.com/pypi/#{dependency_name}/json"
        stub_request(:get, pypi_url).to_return(status: 404, body: "")
        stub_request(:get, private_url)
          .with(basic_auth: %w(username password))
          .to_return(status: 200, body: pypi_response)
      end

      it { is_expected.to eq("https://github.com/spotify/luigi") }

      context "with the creds passed as a token" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }), Dependabot::Credential.new({
            "type" => "python_index",
            "index-url" => "https://pypi.posrip.com/pypi/",
            "token" => "username:password"
          })]
        end

        it { is_expected.to eq("https://github.com/spotify/luigi") }
      end

      context "with the creds using an email address and basic auth" do
        let(:credentials) do
          [Dependabot::Credential.new({
            "type" => "git_source",
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          }), Dependabot::Credential.new({
            "type" => "python_index",
            "index-url" => "https://user@mail.co:password@pypi.posrip.com/pypi/"
          })]
        end

        before do
          private_url = "https://pypi.posrip.com/pypi/#{dependency_name}/json"
          stub_request(:get, private_url)
            .with(basic_auth: %w(user@mail.co password))
            .to_return(status: 200, body: pypi_response)
        end

        it { is_expected.to eq("https://github.com/spotify/luigi") }
      end

      context "when isn't used" do
        before do
          private_url = "https://pypi.posrip.com/pypi/#{dependency_name}/json"
          stub_request(:get, private_url).to_return(status: 404, body: "")
          stub_request(:get, pypi_url)
            .to_return(status: 200, body: pypi_response)
        end

        it { is_expected.to eq("https://github.com/spotify/luigi") }

        context "when it doesn't return json" do
          before do
            private_url = "https://pypi.posrip.com/pypi/#{dependency_name}/json"
            stub_request(:get, private_url)
              .to_return(status: 200, body: "<!DOCTYPE html>")
          end

          it { is_expected.to eq("https://github.com/spotify/luigi") }
        end
      end
    end

    context "when the dependency came from a local repository" do
      let(:pypi_response) { fixture("pypi", "pypi_response.json") }
      let(:version) { "1.0+gc.1" }

      it { is_expected.to be_nil }

      it "doesn't call pypi" do
        source_url
        expect(WebMock).not_to have_requested(:get, pypi_url).once
      end
    end

    context "when there is a bitbucket link in the pypi response" do
      let(:pypi_response) { fixture("pypi", "pypi_response_bitbucket.json") }

      it { is_expected.to eq("https://bitbucket.org/spotify/luigi") }

      it "caches the call to pypi" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, pypi_url).once
      end
    end

    context "when there is a source link in the pypi description" do
      let(:pypi_response) do
        fixture("pypi", "pypi_response_description_source.json")
      end

      context "when dealing with a different dependency" do
        before do
          stub_request(:get, "https://github.com/benjaminp/six")
            .to_return(status: 404, body: "")
        end

        it { is_expected.to be_nil }

        it "caches the call to pypi" do
          2.times { source_url }
          expect(WebMock).to have_requested(:get, pypi_url).once
        end
      end

      context "when dealing with this dependency" do
        let(:dependency_name) { "six" }

        it { is_expected.to eq("https://github.com/benjaminp/six") }

        it "caches the call to pypi" do
          2.times { source_url }
          expect(WebMock).to have_requested(:get, pypi_url).once
        end

        context "with an unexpected name" do
          let(:dependency_name) { "python-six" }

          before do
            stub_request(:get, "https://github.com/benjaminp/six")
              .to_return(status: 200, body: "python-six")
          end

          it { is_expected.to eq("https://github.com/benjaminp/six") }
        end
      end
    end

    context "when there is not a recognised source link in the pypi response" do
      let(:pypi_response) { fixture("pypi", "pypi_response_no_source.json") }

      before do
        stub_request(:get, "http://initd.org/psycopg/")
          .to_return(status: 200, body: "no details")
      end

      it { is_expected.to be_nil }

      it "caches the call to pypi" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, pypi_url).once
      end

      it "caches the call to the homepage" do
        2.times { source_url }
        expect(WebMock)
          .to have_requested(:get, "http://initd.org/psycopg/").once
      end

      context "when the homepage does an infinite redirect" do
        let(:redirect_url) { "http://initd.org/Psycopg/" }

        before do
          stub_request(:get, "http://initd.org/psycopg/")
            .to_return(status: 302, headers: { "Location" => redirect_url })
          stub_request(:get, redirect_url)
            .to_return(
              status: 302,
              headers: { "Location" => "http://initd.org/psycopg/" }
            )
        end

        it { is_expected.to be_nil }
      end

      context "when there are details on the home page" do
        before do
          stub_request(:get, "http://initd.org/psycopg/")
            .to_return(
              status: 200,
              body: fixture("psycopg_homepage.html")
            )
        end

        context "when dealing with this dependency" do
          let(:dependency_name) { "psycopg2" }

          it { is_expected.to eq("https://github.com/psycopg/psycopg2") }

          context "with an unexpected name" do
            let(:dependency_name) { "python-psycopg2" }

            before do
              stub_request(:get, "https://github.com/psycopg/psycopg2")
                .to_return(status: 200, body: "python-psycopg2")
            end

            it { is_expected.to eq("https://github.com/psycopg/psycopg2") }
          end
        end

        context "when dealing with another dependency" do
          let(:dependency_name) { "luigi" }

          before do
            stub_request(:get, "https://github.com/psycopg/psycopg2")
              .to_return(status: 200, body: "python-psycopg2")
          end

          it { is_expected.to be_nil }
        end
      end
    end

    context "when the pypi link resolves to a redirect" do
      let(:redirect_url) { "https://pypi.org/pypi/LuiGi/json" }
      let(:pypi_response) { fixture("pypi", "pypi_response.json") }

      before do
        stub_request(:get, pypi_url)
          .to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url)
          .to_return(status: 200, body: pypi_response)
      end

      it { is_expected.to eq("https://github.com/spotify/luigi") }
    end

    context "when the dependency has extras" do
      let(:dependency_name) { "celery[redis]" }
      let(:version) { "4.3" }
      let(:pypi_url) { "https://pypi.org/pypi/celery/json" }
      let(:pypi_response) { fixture("pypi", "pypi_response_extras.json") }

      it { is_expected.to eq("https://github.com/celery/celery") }
    end

    context "when the dependency source is in project_urls" do
      let(:pypi_response) { fixture("pypi", "pypi_response_project_urls_source.json") }

      it { is_expected.to eq("https://github.com/xxxxx/django-split-settings") }
    end
  end

  describe "#homepage_url" do
    subject(:homepage_url) { finder.homepage_url }

    let(:pypi_url) { "https://pypi.org/pypi/#{dependency_name}/json" }

    before do
      stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
    end

    context "when there is a homepage link in the pypi response" do
      let(:pypi_response) { fixture("pypi", "pypi_response_no_source.json") }

      it "returns the specified homepage" do
        expect(homepage_url).to eq("http://initd.org/psycopg/")
      end
    end
  end
end
