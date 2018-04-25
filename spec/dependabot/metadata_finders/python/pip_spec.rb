# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/metadata_finders/python/pip"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Dependabot::MetadataFinders::Python::Pip do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      version: version,
      requirements: [
        {
          file: "requirements.txt",
          requirement: "==#{version}",
          groups: [],
          source: nil
        }
      ],
      package_manager: "pip"
    )
  end
  subject(:finder) do
    described_class.new(dependency: dependency, credentials: credentials)
  end
  let(:credentials) do
    [{
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:dependency_name) { "luigi" }
  let(:version) { "1.0" }

  describe "#source_url" do
    subject(:source_url) { finder.source_url }
    let(:pypi_url) { "https://pypi.python.org/pypi/#{dependency_name}/json" }

    before do
      stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
    end

    context "when there is a github link in the pypi response" do
      let(:pypi_response) { fixture("python", "pypi_response.json") }

      it { is_expected.to eq("https://github.com/spotify/luigi") }

      it "caches the call to pypi" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, pypi_url).once
      end
    end

    context "with a private index" do
      let(:credentials) do
        [
          {
            "host" => "github.com",
            "username" => "x-access-token",
            "password" => "token"
          },
          {
            "index-url" => "https://username:password@pypi.posrip.com/pypi/"
          }
        ]
      end
      before do
        private_url = "https://pypi.posrip.com/pypi/#{dependency_name}/json"
        stub_request(:get, pypi_url).to_return(status: 404, body: "")
        stub_request(:get, private_url).
          with(basic_auth: %w(username password)).
          to_return(status: 200, body: pypi_response)
      end
      let(:pypi_response) { fixture("python", "pypi_response.json") }

      it { is_expected.to eq("https://github.com/spotify/luigi") }

      context "that isn't used" do
        before do
          private_url = "https://pypi.posrip.com/pypi/#{dependency_name}/json"
          stub_request(:get, private_url).to_return(status: 404, body: "")
          stub_request(:get, pypi_url).
            to_return(status: 200, body: pypi_response)
        end

        it { is_expected.to eq("https://github.com/spotify/luigi") }

        context "because it doesn't return json" do
          before do
            private_url = "https://pypi.posrip.com/pypi/#{dependency_name}/json"
            stub_request(:get, private_url).
              to_return(status: 200, body: "<!DOCTYPE html>")
          end

          it { is_expected.to eq("https://github.com/spotify/luigi") }
        end
      end
    end

    context "when the dependency came from a local repository" do
      let(:pypi_response) { fixture("python", "pypi_response.json") }
      let(:version) { "1.0+gc.1" }

      it { is_expected.to be_nil }

      it "doesn't call pypi" do
        source_url
        expect(WebMock).to_not have_requested(:get, pypi_url).once
      end
    end

    context "when there is a bitbucket link in the pypi response" do
      let(:pypi_response) { fixture("python", "pypi_response_bitbucket.json") }

      it { is_expected.to eq("https://bitbucket.org/spotify/luigi") }

      it "caches the call to pypi" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, pypi_url).once
      end
    end

    context "when there is a source link in the pypi description" do
      let(:pypi_response) do
        fixture("python", "pypi_response_description_source.json")
      end

      context "for a different dependency" do
        it { is_expected.to be_nil }

        it "caches the call to pypi" do
          2.times { source_url }
          expect(WebMock).to have_requested(:get, pypi_url).once
        end
      end

      context "for a different dependency" do
        let(:dependency_name) { "six" }

        it { is_expected.to eq("https://github.com/benjaminp/six") }

        it "caches the call to pypi" do
          2.times { source_url }
          expect(WebMock).to have_requested(:get, pypi_url).once
        end
      end
    end

    context "when there is not a recognised source link in the pypi response" do
      let(:pypi_response) { fixture("python", "pypi_response_no_source.json") }

      it { is_expected.to be_nil }

      it "caches the call to pypi" do
        2.times { source_url }
        expect(WebMock).to have_requested(:get, pypi_url).once
      end
    end

    context "when the pypi link resolves to a redirect" do
      let(:redirect_url) { "https://pypi.python.org/pypi/LuiGi/json" }
      let(:pypi_response) { fixture("python", "pypi_response.json") }

      before do
        stub_request(:get, pypi_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(status: 200, body: pypi_response)
      end

      it { is_expected.to eq("https://github.com/spotify/luigi") }
    end
  end

  describe "#homepage_url" do
    subject(:homepage_url) { finder.homepage_url }
    let(:pypi_url) { "https://pypi.python.org/pypi/#{dependency_name}/json" }

    before do
      stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
    end

    context "when there is a homepage link in the pypi response" do
      let(:pypi_response) { fixture("python", "pypi_response_no_source.json") }

      it "returns the specified homepage" do
        expect(homepage_url).to eq("http://initd.org/psycopg/")
      end
    end
  end
end
