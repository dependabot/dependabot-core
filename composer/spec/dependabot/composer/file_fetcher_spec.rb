# frozen_string_literal: true

require "spec_helper"
require "dependabot/composer/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Composer::FileFetcher do
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
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  before do
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")

    stub_request(:get, url + "?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "contents_composer_repo.json"),
        headers: { "content-type" => "application/json" }
      )
    stub_request(:get, url + "composer.json?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "composer_json_content.json"),
        headers: { "content-type" => "application/json" }
      )
    stub_request(:get, url + "composer.lock?ref=sha").
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "composer_lock_content.json"),
        headers: { "content-type" => "application/json" }
      )
  end

  it "fetches the composer.json and composer.lock" do
    expect(file_fetcher_instance.files.map(&:name)).
      to match_array(%w(composer.json composer.lock))
  end

  context "without a composer.lock" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_composer_repo_no_lockfile.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "composer.lock?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
    end

    it "fetches the composer.json" do
      expect(file_fetcher_instance.files.map(&:name)).to eq(["composer.json"])
    end
  end

  context "with an auth.json" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_composer_repo_with_auth.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, url + "auth.json?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "composer_json_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the auth.json" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(composer.json composer.lock auth.json))
    end
  end

  context "without a composer.json" do
    before do
      stub_request(:get, url + "composer.json?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
    end

    it "raises a helpful error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotFound)
    end
  end

  context "with a bad composer.json" do
    before do
      stub_request(:get, File.join(url, "composer.json?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemfile_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises a DependencyFileNotParseable error" do
      expect { file_fetcher_instance.files }.
        to raise_error(Dependabot::DependencyFileNotParseable) do |error|
          expect(error.file_name).to eq("composer.json")
        end
    end
  end

  context "with a path source" do
    before do
      stub_request(:get, url + "composer.json?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "composer_json_with_path_deps.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "components?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_ruby_nested_path_directory.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "components/bump-core/composer.json?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "composer_json_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "components/another-dep/composer.json?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "composer_json_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the composer.json, composer.lock and the path dependency" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(
          %w(composer.json composer.lock components/bump-core/composer.json
             components/another-dep/composer.json)
        )
    end

    context "specified as a hash" do
      before do
        stub_request(:get, url + "composer.json?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "composer_json_with_path_deps_hash.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the composer.json, composer.lock and the path dependency" do
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(
            %w(composer.json composer.lock components/bump-core/composer.json
               components/another-dep/composer.json)
          )
      end
    end

    context "specified as an array with surprising entries" do
      before do
        stub_request(:get, url + "composer.json?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "composer_json_with_odd_entries.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the composer.json, composer.lock and the path dependency" do
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(
            %w(composer.json composer.lock components/bump-core/composer.json
               components/another-dep/composer.json)
          )
      end
    end

    context "that doesn't exist but also isn't used" do
      before do
        stub_request(:get, url + "components?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 404)
      end

      it "fetches the composer.json and composer.lock" do
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(composer.json composer.lock))
      end

      context "because there is no lockfile" do
        before do
          stub_request(:get, url + "?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body:
                fixture("github", "contents_composer_repo_no_lockfile.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "composer.lock?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 404)
        end

        it "fetches the composer.json" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(composer.json))
        end
      end
    end

    context "and a directory" do
      let(:directory) { "my/app/" }
      let(:base_url) do
        "https://api.github.com/repos/gocardless/bump/contents/"
      end
      let(:url) { base_url + "my/app/" }

      before do
        stub_request(:get, base_url + "my/app?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_composer_repo.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the composer.json, composer.lock and the path dependency" do
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(
            %w(composer.json composer.lock components/bump-core/composer.json
               components/another-dep/composer.json)
          )
      end

      context "when the path dependencies are relative to the root" do
        before do
          stub_request(:get, url + "components?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 404)
          stub_request(:get, base_url + "components?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body:
                fixture("github", "contents_ruby_nested_path_directory.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "composer.lock?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "composer_lock_with_path_deps.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(
            :get,
            url + "components/path_dep/composer.json?ref=sha"
          ).with(headers: { "Authorization" => "token token" }).
            to_return(status: 404)
          stub_request(
            :get,
            url + "components/path_dep?ref=sha"
          ).with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: "[]",
              headers: { "content-type" => "application/json" }
            )
          stub_request(
            :get,
            base_url + "components/path_dep/composer.json?ref=sha"
          ).with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "composer_json_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches the composer.json, composer.lock and the path dependency" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(
              %w(composer.json composer.lock components/path_dep/composer.json)
            )
        end

        context "and a path starting with '..' was specified" do
          before do
            stub_request(:get, url + "composer.json?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github",
                              "composer_json_with_relative_path_deps.json"),
                headers: { "content-type" => "application/json" }
              )
            stub_request(:get, url + "composer.lock?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github",
                              "composer_lock_with_relative_path_deps.json"),
                headers: { "content-type" => "application/json" }
              )
            stub_request(:get, base_url + "my/components?ref=sha").
              with(headers: { "Authorization" => "token token" }).
              to_return(status: 404)
            stub_request(
              :get,
              base_url + "my?ref=sha"
            ).with(headers: { "Authorization" => "token token" }).
              to_return(status: 404)
            stub_request(
              :get,
              base_url + "my/components/path_dep/composer.json?ref=sha"
            ).with(headers: { "Authorization" => "token token" }).
              to_return(status: 404)
            stub_request(
              :get,
              base_url + "my/components/path_dep?ref=sha"
            ).with(headers: { "Authorization" => "token token" }).
              to_return(status: 404)
          end

          it "fetches the path dependency" do
            expect(file_fetcher_instance.files.map(&:name)).
              to match_array(
                %w(composer.json composer.lock
                   ../components/path_dep/composer.json)
              )
          end
        end
      end
    end
  end
end
