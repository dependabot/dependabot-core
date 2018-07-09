# frozen_string_literal: true

require "dependabot/file_fetchers/java_script/npm_and_yarn"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::JavaScript::NpmAndYarn do
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
  let(:url) { "https://api.github.com/repos/gocardless/bump/contents/" }
  let(:directory) { "/" }
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
        body: fixture("github", "contents_js_npm.json"),
        headers: { "content-type" => "application/json" }
      )

    stub_request(:get, File.join(url, "package.json?ref=sha")).
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "package_json_content.json"),
        headers: { "content-type" => "application/json" }
      )

    stub_request(:get, File.join(url, "package-lock.json?ref=sha")).
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", "package_lock_content.json"),
        headers: { "content-type" => "application/json" }
      )
  end

  context "with a .npmrc file" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_js_npm_with_config.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, ".npmrc?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "npmrc_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the .npmrc" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name)).to include(".npmrc")
      expect(file_fetcher_instance.files.map(&:name)).
        to include("package-lock.json")
    end

    context "that specifies no package-lock" do
      before do
        stub_request(:get, File.join(url, ".npmrc?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "npmrc_content_no_lockfile.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "doesn't include the package-lock" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).to include(".npmrc")
        expect(file_fetcher_instance.files.map(&:name)).
          to_not include("package-lock.json")
      end
    end
  end

  context "without a package-lock.json file or a yarn.lock" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_js_library.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "package-lock.json?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
    end

    it "fetches the package.json" do
      expect(file_fetcher_instance.files.map(&:name)).to eq(["package.json"])
      expect(file_fetcher_instance.files.first.type).to eq("file")
    end

    context "with a path dependency" do
      before do
        stub_request(:get, File.join(url, "package.json?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "package_json_with_path_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      context "that has an unfetchable path" do
        before do
          stub_request(:get, File.join(url, "deps/etag/package.json?ref=sha")).
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 404)
        end

        it "fetches the package.json and ignores the missing path dep" do
          expect(file_fetcher_instance.files.map(&:name)).
            to eq(["package.json"])
          expect(file_fetcher_instance.files.first.type).to eq("file")
        end
      end
    end
  end

  context "with a yarn.lock but no package-lock.json file" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_js_yarn.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "package-lock.json?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
      stub_request(:get, File.join(url, "yarn.lock?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "yarn_lock_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the package.json and yarn.lock" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(package.json yarn.lock))
    end
  end

  context "with a package-lock.json file but no yarn.lock" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_js_npm.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "yarn.lock?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
      stub_request(:get, File.join(url, "package-lock.json?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "package_lock_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the package.json and package-lock.json" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(package.json package-lock.json))
    end
  end

  context "with both a package-lock.json file and a yarn.lock" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_js_npm_and_yarn.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "yarn.lock?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "yarn_lock_content.json"),
          headers: { "content-type" => "application/json" }
        )
      stub_request(:get, File.join(url, "package-lock.json?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "package_lock_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the package.json, package-lock.json and yarn.lock" do
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(package.json package-lock.json yarn.lock))
    end
  end

  context "with a path dependency" do
    before do
      stub_request(:get, File.join(url, "package.json?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "package_json_with_path_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    context "with a bad package.json" do
      before do
        stub_request(:get, File.join(url, "package.json?ref=sha")).
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
            expect(error.file_name).to eq("package.json")
          end
      end
    end

    context "that has a fetchable path" do
      before do
        stub_request(:get, File.join(url, "deps/etag/package.json?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "package_json_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches package.json from path dependency" do
        expect(file_fetcher_instance.files.count).to eq(3)
        expect(file_fetcher_instance.files.map(&:name)).
          to include("deps/etag/package.json")
        path_file = file_fetcher_instance.files.
                    find { |f| f.name == "deps/etag/package.json" }
        expect(path_file.type).to eq("path_dependency")
      end
    end

    context "that has an unfetchable path" do
      before do
        stub_request(:get, File.join(url, "deps/etag/package.json?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 404)
      end

      context "when the path dep doesn't appear in the lockfile" do
        it "raises a PathDependenciesNotReachable error with details" do
          expect { file_fetcher_instance.files }.
            to raise_error(
              Dependabot::PathDependenciesNotReachable,
              "The following path based dependencies could not be retrieved: " \
              "etag"
            )
        end
      end

      context "when the path dep does appear in the lockfile" do
        before do
          stub_request(:get, File.join(url, "package-lock.json?ref=sha")).
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "package_lock_with_path_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "builds an imitation path dependency" do
          expect(file_fetcher_instance.files.count).to eq(3)
          expect(file_fetcher_instance.files.map(&:name)).
            to include("deps/etag/package.json")
          path_file = file_fetcher_instance.files.
                      find { |f| f.name == "deps/etag/package.json" }
          expect(path_file.type).to eq("path_dependency")
          expect(path_file.content).
            to eq("{\"name\":\"etag\",\"version\":\"0.0.1\"}")
        end
      end

      context "that only appears in the lockfile" do
        before do
          stub_request(:get, url + "?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "contents_js_npm.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, File.join(url, "package.json?ref=sha")).
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "package_json_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, File.join(url, "package-lock.json?ref=sha")).
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "package_lock_with_path_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "builds an imitation path dependency" do
          expect(file_fetcher_instance.files.count).to eq(3)
          expect(file_fetcher_instance.files.map(&:name)).
            to include("deps/etag/package.json")
          path_file = file_fetcher_instance.files.
                      find { |f| f.name == "deps/etag/package.json" }
          expect(path_file.type).to eq("path_dependency")
        end
      end
    end
  end

  context "with workspaces" do
    before do
      allow(file_fetcher_instance).to receive(:commit).and_return("sha")

      stub_request(:get, File.join(url, "package.json?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "package_json_with_workspaces_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "yarn.lock?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "yarn_lock_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    context "that have fetchable paths" do
      before do
        stub_request(:get, File.join(url, "packages?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "packages_files.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(
          :get,
          File.join(url, "packages/package1/package.json?ref=sha")
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "package_json_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(
          :get,
          File.join(url, "packages/package2/package.json?ref=sha")
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "package_json_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(
          :get,
          File.join(url, "other_package/package.json?ref=sha")
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "package_json_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches package.json from the workspace dependencies" do
        expect(file_fetcher_instance.files.count).to eq(5)
        expect(file_fetcher_instance.files.map(&:name)).
          to include("packages/package2/package.json")
      end

      context "specified using a hash" do
        before do
          stub_request(:get, File.join(url, "package.json?ref=sha")).
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "package_json_with_hash_workspaces.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches package.json from the workspace dependencies" do
          expect(file_fetcher_instance.files.count).to eq(5)
          expect(file_fetcher_instance.files.map(&:name)).
            to include("packages/package2/package.json")
        end
      end

      context "in a directory" do
        let(:url) do
          "https://api.github.com/repos/gocardless/bump/contents/etc"
        end
        let(:directory) { "/etc" }
        before do
          stub_request(:get, File.join(url, "packages?ref=sha")).
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "packages_files_nested.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches package.json from the workspace dependencies" do
          expect(file_fetcher_instance.files.count).to eq(5)
          expect(file_fetcher_instance.files.map(&:name)).
            to include("packages/package2/package.json")
        end
      end
    end

    context "that has an unfetchable path" do
      before do
        stub_request(:get, File.join(url, "packages?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "packages_files.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(
          :get,
          File.join(url, "packages/package1/package.json?ref=sha")
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "package_json_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(
          :get,
          File.join(url, "packages/package2/package.json?ref=sha")
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "package_json_content.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(
          :get,
          File.join(url, "other_package/package.json?ref=sha")
        ).with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 404,
            body: fixture("github", "package_json_content.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "raises a PathDependenciesNotReachable error with details" do
        expect { file_fetcher_instance.files }.
          to raise_error(
            Dependabot::PathDependenciesNotReachable,
            "The following path based dependencies could not be retrieved: " \
            "other_package/package.json"
          )
      end
    end
  end
end
