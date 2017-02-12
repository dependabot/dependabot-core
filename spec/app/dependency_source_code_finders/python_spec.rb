require "spec_helper"
require "./app/dependency_source_code_finders/python"

RSpec.describe DependencySourceCodeFinders::Python do
  subject(:finder) { described_class.new(dependency_name: dependency_name) }
  let(:dependency_name) { "luigi" }

  describe "#github_repo" do
    subject(:github_repo) { finder.github_repo }
    let(:pypi_url) { "https://pypi.python.org/pypi/luigi/json" }

    before do
      stub_request(:get, pypi_url).
        to_return(status: 200, body: pypi_response)
    end

    context "when there is a github link in the pypi response" do
      let(:pypi_response) { fixture("pypi_response.json") }

      it { is_expected.to eq("spotify/luigi") }

      it "caches the call to pypi" do
        2.times { github_repo }
        expect(WebMock).to have_requested(:get, pypi_url).once
      end
    end

    context "when there is not a github link in the pypi response" do
      let(:pypi_response) { fixture("pypi_response_no_github.json") }

      it { is_expected.to be_nil }

      it "caches the call to pypi" do
        2.times { github_repo }
        expect(WebMock).to have_requested(:get, pypi_url).once
      end
    end
  end
end
