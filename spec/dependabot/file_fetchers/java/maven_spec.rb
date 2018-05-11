# frozen_string_literal: true

require "dependabot/file_fetchers/java/maven"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Java::Maven do
  it_behaves_like "a dependency file fetcher"

  let(:source) { { host: "github", repo: "gocardless/bump" } }
  let(:file_fetcher_instance) do
    described_class.new(
      source: source,
      credentials: credentials,
      directory: directory
    )
  end
  let(:directory) { "/" }
  let(:github_url) { "https://api.github.com/" }
  let(:url) { github_url + "repos/gocardless/bump/contents/" }
  let(:credentials) do
    [{
      "type" => "git",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  context "with a basic pom" do
    before do
      stub_request(:get, File.join(url, "pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_java_basic_pom.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the pom" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(pom.xml))
    end
  end

  context "with a multimodule pom" do
    before do
      stub_request(:get, File.join(url, "pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_java_multimodule_pom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "util/pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_java_basic_pom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "business-app/pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_java_basic_pom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "legacy/pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_java_basic_pom.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the poms" do
      expect(file_fetcher_instance.files.count).to eq(4)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(
          %w(pom.xml util/pom.xml business-app/pom.xml legacy/pom.xml)
        )
    end

    context "with a nested multimodule pom" do
      before do
        stub_request(:get, File.join(url, "util/pom.xml?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_java_multimodule_pom.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, File.join(url, "util/util/pom.xml?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_java_basic_pom.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, File.join(url, "util/business-app/pom.xml?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_java_basic_pom.json"),
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, File.join(url, "util/legacy/pom.xml?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_java_basic_pom.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the poms" do
        expect(file_fetcher_instance.files.count).to eq(7)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(
            %w(
              pom.xml util/pom.xml business-app/pom.xml legacy/pom.xml
              util/util/pom.xml util/legacy/pom.xml util/business-app/pom.xml
            )
          )
      end

      context "when asked to fetch only a subdirectory" do
        let(:directory) { "/util/util" }

        it "fetches the relevant poms" do
          expect(file_fetcher_instance.files.count).to eq(3)
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(pom.xml ../pom_parent.xml ../../pom_parent.xml))
        end
      end

      context "where multiple poms require the same file" do
        before do
          stub_request(:get, File.join(url, "util/legacy/pom.xml?ref=sha")).
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "contents_java_relative_module_pom.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the poms uniquely" do
          expect(file_fetcher_instance.files.count).to eq(7)
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(
              %w(
                pom.xml util/pom.xml business-app/pom.xml legacy/pom.xml
                util/util/pom.xml util/legacy/pom.xml util/business-app/pom.xml
              )
            )
          expect(WebMock).to have_requested(
            :get,
            File.join(url, "util/util/pom.xml?ref=sha")
          ).once
        end
      end
    end
  end
end
