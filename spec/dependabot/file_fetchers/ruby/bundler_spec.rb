# frozen_string_literal: true

require "dependabot/file_fetchers/ruby/bundler"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Ruby::Bundler do
  it_behaves_like "a dependency file fetcher"

  context "with a .ruby-version file" do
    let(:github_client) { Octokit::Client.new(access_token: "token") }
    let(:file_fetcher_instance) do
      described_class.new(repo: "gocardless/bump", github_client: github_client)
    end

    let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "business_files_no_gemspec.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemfile_with_ruby_file_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemfile_lock_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    context "that is fetchable" do
      before do
        stub_request(:get, url + ".ruby-version?ref=sha").
          to_return(
            status: 200,
            body: fixture("github", "ruby_version_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the ruby-version file" do
        expect(file_fetcher_instance.files.count).to eq(3)
        expect(file_fetcher_instance.files.map(&:name)).
          to include(".ruby-version")
      end
    end

    context "that has an unfetchable path" do
      before do
        stub_request(:get, url + ".ruby-version?ref=sha").
          to_return(status: 404)
      end

      it "quietly ignores the error (we'll serve a different one later)" do
        expect(file_fetcher_instance.files.count).to eq(2)
      end
    end
  end

  context "with a path dependency" do
    let(:github_client) { Octokit::Client.new(access_token: "token") }
    let(:file_fetcher_instance) do
      described_class.new(repo: "gocardless/bump", github_client: github_client)
    end

    let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "business_files_no_gemspec.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemfile_with_path_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemfile_lock_with_path_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    context "that has a fetchable path" do
      before do
        stub_request(:get, url + "plugins/bump-core/bump-core.gemspec?ref=sha").
          to_return(
            status: 200,
            body: fixture("github", "gemspec_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches gemspec from path dependency" do
        expect(file_fetcher_instance.files.count).to eq(3)
        expect(file_fetcher_instance.files.map(&:name)).
          to include("plugins/bump-core/bump-core.gemspec")
      end
    end

    context "that has an unfetchable path" do
      before do
        stub_request(:get, url + "plugins/bump-core/bump-core.gemspec?ref=sha").
          to_return(status: 404)
      end

      it "raises a PathDependenciesNotReachable error with details" do
        expect { file_fetcher_instance.files }.
          to raise_error(
            Dependabot::PathDependenciesNotReachable,
            "The following path based dependencies could not be retrieved: " \
            "bump-core"
          )
      end
    end
  end

  context "with a child Gemfile" do
    let(:github_client) { Octokit::Client.new(access_token: "token") }
    let(:file_fetcher_instance) do
      described_class.new(repo: "gocardless/bump", github_client: github_client)
    end

    let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "business_files_no_gemspec.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemfile_with_eval_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        to_return(status: 404)
    end

    context "that uses a variable name" do
      before do
        stub_request(:get, url + "Gemfile?ref=sha").
          to_return(
            status: 200,
            body: fixture("github", "gemfile_with_eval_variable_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      # TODO: ideally we'd be able to handle cases like this
      it "doesn't fetch the child Gemfile, but doesn't error" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name)).
          to eq(["Gemfile"])
      end
    end

    context "that has a fetchable path" do
      before do
        stub_request(:get, url + "backend/Gemfile?ref=sha").
          to_return(
            status: 200,
            body: fixture("github", "gemfile_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the child Gemfile" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).
          to include("backend/Gemfile")
      end

      context "and is circular" do
        before do
          stub_request(:get, url + "Gemfile?ref=sha").
            to_return(
              status: 200,
              body: fixture("github", "gemfile_with_circular.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "only fetches the additional requirements once" do
          expect(file_fetcher_instance.files.count).to eq(1)
        end
      end

      context "and cascades more than once" do
        before do
          stub_request(:get, url + "backend/Gemfile?ref=sha").
            to_return(
              status: 200,
              body: fixture("github", "gemfile_with_eval_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "backend/backend/Gemfile?ref=sha").
            to_return(
              status: 200,
              body: fixture("github", "gemfile_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the additional requirements" do
          expect(file_fetcher_instance.files.count).to eq(3)
          expect(file_fetcher_instance.files.map(&:name)).
            to include("backend/Gemfile").
            and include("backend/backend/Gemfile")
        end
      end
    end

    context "that has an unfetchable path" do
      before do
        stub_request(:get, url + "backend/Gemfile?ref=sha").
          to_return(status: 404)
      end

      it "raises a DependencyFileNotFound error with details" do
        expect { file_fetcher_instance.files }.
          to raise_error(Dependabot::DependencyFileNotFound)
      end
    end
  end

  context "with a gemspec" do
    let(:github_client) { Octokit::Client.new(access_token: "token") }
    let(:file_fetcher_instance) do
      described_class.new(repo: "gocardless/bump", github_client: github_client)
    end

    let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "business_files_no_gemspec.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemfile_with_gemspec_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemfile_lock_with_gemspec_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "example.gemspec?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemspec_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches gemspec" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name)).
        to include("example.gemspec")
    end
  end

  context "with only a gemspec and a Gemfile" do
    let(:github_client) { Octokit::Client.new(access_token: "token") }
    let(:file_fetcher_instance) do
      described_class.new(repo: "gocardless/bump", github_client: github_client)
    end

    let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "business_files.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemfile_with_gemspec_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        to_return(status: 404)

      stub_request(:get, url + "business.gemspec?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemspec_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches gemspec" do
      expect(file_fetcher_instance.files.count).to eq(2)
      expect(file_fetcher_instance.files.map(&:name)).
        to include("business.gemspec")
    end
  end

  context "with only a gemspec" do
    let(:github_client) { Octokit::Client.new(access_token: "token") }
    let(:file_fetcher_instance) do
      described_class.new(repo: "gocardless/bump", github_client: github_client)
    end

    let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "business_files.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        to_return(status: 404)

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        to_return(status: 404)

      stub_request(:get, url + "business.gemspec?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemspec_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the gemspec" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to include("business.gemspec")
    end
  end

  context "with only a Gemfile" do
    let(:github_client) { Octokit::Client.new(access_token: "token") }
    let(:file_fetcher_instance) do
      described_class.new(repo: "gocardless/bump", github_client: github_client)
    end

    let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "business_files_no_gemspec.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemfile_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        to_return(status: 404)
    end

    it "fetches the Gemfile" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to include("Gemfile")
    end
  end

  context "with only a Gemfile.lock" do
    let(:github_client) { Octokit::Client.new(access_token: "token") }
    let(:file_fetcher_instance) do
      described_class.new(repo: "gocardless/bump", github_client: github_client)
    end

    let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }

    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, url + "?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "business_files_no_gemspec.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        to_return(status: 404)

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        to_return(
          status: 200,
          body: fixture("github", "gemfile_lock_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error do |error|
          expect(error).to be_a(Dependabot::DependencyFileNotFound)
          expect(error.file_path).to eq("/Gemfile")
        end
    end
  end
end
