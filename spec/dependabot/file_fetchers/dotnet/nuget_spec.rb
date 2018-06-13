# frozen_string_literal: true

require "dependabot/file_fetchers/dotnet/nuget"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Dotnet::Nuget do
  it_behaves_like "a dependency file fetcher"

  let(:source) do
    Dependabot::Source.new(
      provider: "github",
      repo: "gocardless/bump",
      directory: directory
    )
  end
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:directory) { "/" }
  let(:github_url) { "https://api.github.com/" }
  let(:url) { github_url + "repos/gocardless/bump/contents/" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  context "with a .csproj" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_dotnet_repo.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "Nancy.csproj?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_dotnet_csproj_basic.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the .csproj" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Nancy.csproj))
    end

    context "that imports another project" do
      before do
        stub_request(:get, File.join(url, "Nancy.csproj?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_dotnet_csproj_with_import.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, File.join(url, "commonprops.props?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_dotnet_csproj_basic.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the imported file" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(Nancy.csproj commonprops.props))
      end

      context "that imports itself" do
        before do
          stub_request(:get, File.join(url, "commonprops.props?ref=sha")).
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body:
                fixture("github", "contents_dotnet_csproj_with_import.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "only fetches the imported file once" do
          expect(file_fetcher_instance.files.count).to eq(2)
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(Nancy.csproj commonprops.props))
        end
      end

      context "that imports another (granchild) file" do
        before do
          stub_request(:get, File.join(url, "commonprops.props?ref=sha")).
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body:
                fixture("github", "contents_dotnet_csproj_with_import2.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, File.join(url, "commonprops2.props?ref=sha")).
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body:
                fixture("github", "contents_dotnet_csproj_with_import.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "only fetches the imported file once" do
          expect(file_fetcher_instance.files.count).to eq(3)
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(
              %w(Nancy.csproj commonprops.props commonprops2.props)
            )
        end
      end
    end
  end

  context "with a .vbproj" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_dotnet_repo_vb.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "Nancy.vbproj?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_dotnet_csproj_basic.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the .vbproj" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Nancy.vbproj))
    end
  end

  context "with a .fsproj" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_dotnet_repo_fs.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "Nancy.fsproj?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_dotnet_csproj_basic.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the .vbproj" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Nancy.fsproj))
    end
  end

  context "without any project files" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_ruby.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises a Dependabot::DependencyFileNotFound error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound) do |error|
          expect(error.file_name).to eq("<anything>.csproj")
        end
    end
  end
end
