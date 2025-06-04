# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/git_submodules/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::GitSubmodules::FileFetcher do
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: "/"
    )
  end

  it_behaves_like "a dependency file fetcher"

  context "with submodules" do
    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")
    end

    context "with a GitHub source" do
      let(:source) do
        Dependabot::Source.new(
          provider: "github",
          repo: "gocardless/bump",
          directory: "/"
        )
      end

      before do
        stub_request(:get, url + ".gitmodules?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "gitmodules.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      context "when dealing with a fetchable path" do
        before do
          stub_request(:get, url + "about/documents?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "submodule.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "manifesto?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "submodule.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the submodules" do
          expect(file_fetcher_instance.files.count).to eq(3)

          expect(file_fetcher_instance.files.first.name).to eq(".gitmodules")
          expect(file_fetcher_instance.files.first.type).to eq("file")

          expect(file_fetcher_instance.files[1].name).to eq("about/documents")
          expect(file_fetcher_instance.files[1].type).to eq("submodule")
          expect(file_fetcher_instance.files.last.content)
            .to eq("d70e943e00a09a3c98c0e4ac9daab112b749cf62")

          expect(file_fetcher_instance.files.last.name).to eq("manifesto")
          expect(file_fetcher_instance.files.last.type).to eq("submodule")
          expect(file_fetcher_instance.files.last.content)
            .to eq("d70e943e00a09a3c98c0e4ac9daab112b749cf62")
        end
      end

      context "when dealing with an unfetchable path" do
        before do
          stub_request(:get, url + "about/documents?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 404)
          stub_request(:get, url + "manifesto?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(status: 404)
        end

        it "raises a DependencyFileNotFound error with details" do
          expect { file_fetcher_instance.files }
            .to raise_error(Dependabot::DependencyFileNotFound)
        end
      end

      context "when the path returns a file" do
        before do
          stub_request(:get, url + "about/documents?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "gemfile_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "manifesto?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "gemfile_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "raises a DependencyFileNotFound error with details" do
          expect { file_fetcher_instance.files }
            .to raise_error(Dependabot::DependencyFileNotFound)
        end
      end

      context "when the path returns a repo" do
        before do
          stub_request(:get, url + "about/documents?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "repo_contents.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "manifesto?ref=sha")
            .with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "repo_contents.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "raises a DependencyFileNotFound error with details" do
          expect { file_fetcher_instance.files }
            .to raise_error(Dependabot::DependencyFileNotFound)
        end
      end
    end

    context "with a GitLab source" do
      let(:source) do
        Dependabot::Source.new(
          provider: "gitlab",
          repo: "gocardless/bump",
          directory: "/"
        )
      end
      let(:url) do
        "https://gitlab.com/api/v4/projects/gocardless%2Fbump/repository/files/"
      end

      before do
        stub_request(:get, url + ".gitmodules?ref=sha")
          .to_return(
            status: 200,
            body: fixture("gitlab", "gitmodules.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      context "when dealing with a fetchable path" do
        before do
          stub_request(:get, url + "about%2Fdocuments?ref=sha")
            .to_return(
              status: 200,
              body: fixture("gitlab", "submodule.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "manifesto?ref=sha")
            .to_return(
              status: 200,
              body: fixture("gitlab", "submodule.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the submodules" do
          expect(file_fetcher_instance.files.count).to eq(3)

          expect(file_fetcher_instance.files.first.name).to eq(".gitmodules")
          expect(file_fetcher_instance.files.first.type).to eq("file")

          expect(file_fetcher_instance.files[1].name).to eq("about/documents")
          expect(file_fetcher_instance.files[1].type).to eq("submodule")
          expect(file_fetcher_instance.files.last.content)
            .to eq("7512a167d6c923f3885f77f62853475ba8f9c171")

          expect(file_fetcher_instance.files.last.name).to eq("manifesto")
          expect(file_fetcher_instance.files.last.type).to eq("submodule")
          expect(file_fetcher_instance.files.last.content)
            .to eq("7512a167d6c923f3885f77f62853475ba8f9c171")
        end
      end

      context "when dealing with an unfetchable path" do
        before do
          stub_request(:get, url + "about%2Fdocuments?ref=sha")
            .to_return(
              status: 404,
              body: fixture("gitlab", "not_found.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "manifesto?ref=sha")
            .to_return(
              status: 404,
              body: fixture("gitlab", "not_found.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "raises a DependencyFileNotFound error with details" do
          expect { file_fetcher_instance.files }
            .to raise_error(Dependabot::DependencyFileNotFound)
        end
      end
    end

    context "with a bad .gitmodules file" do
      before do
        stub_request(:get, url + ".gitmodules?ref=sha")
          .with(headers: { "Authorization" => "token token" })
          .to_return(
            status: 200,
            body: fixture("github", "gemfile_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      # We could raise a DependencyFileNotParseable error here instead?
      specify { expect(file_fetcher_instance.files.count).to eq(1) }
    end
  end
end
