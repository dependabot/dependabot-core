# frozen_string_literal: true

require "dependabot/file_fetchers/ruby/bundler"
require_relative "../shared_examples_for_file_fetchers"

RSpec.describe Dependabot::FileFetchers::Ruby::Bundler do
  it_behaves_like "a dependency file fetcher"

  let(:source) { { host: "github", repo: "gocardless/bump" } }
  let(:file_fetcher_instance) do
    described_class.new(source: source, credentials: credentials)
  end
  let(:github_url) { "https://api.github.com/" }
  let(:url) { github_url + "repos/gocardless/bump/contents/" }
  let(:credentials) do
    [{
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end

  before { allow(file_fetcher_instance).to receive(:commit).and_return("sha") }

  context "with a directory" do
    let(:file_fetcher_instance) do
      described_class.new(
        source: source,
        credentials: credentials,
        directory: "/test"
      )
    end
    let(:url) { "https://api.github.com/repos/gocardless/bump/contents/test" }

    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_ruby.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "Gemfile?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemfile_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "Gemfile.lock?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemfile_lock_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches the files as normal" do
      expect(file_fetcher_instance.files.count).to eq(2)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(Gemfile Gemfile.lock))
    end

    context "that can't be found" do
      before do
        stub_request(:get, url + "?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 404,
            headers: { "content-type" => "application/json" }
          )
      end

      it "raises a DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }.
          to raise_error(Dependabot::DependencyFileNotFound)
      end
    end
  end

  context "with a .ruby-version file" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_ruby.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemfile_with_ruby_file_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemfile_lock_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    before do
      stub_request(:get, url + ".ruby-version?ref=sha").
        with(headers: { "Authorization" => "token token" }).
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

  context "with a path dependency" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_ruby.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemfile_with_path_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemfile_lock_with_path_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    context "that has a fetchable path" do
      before do
        stub_request(:get, url + "plugins/bump-core?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_ruby_path_directory.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, url + "plugins/bump-core/bump-core.gemspec?ref=sha").
          with(headers: { "Authorization" => "token token" }).
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

      context "that is nested" do
        before do
          stub_request(:get, url + "plugins/bump-core?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body:
                fixture("github", "contents_ruby_nested_path_directory.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "plugins/bump-core/bump-core?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "contents_ruby_path_directory.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(
            :get, url + "plugins/bump-core/bump-core/bump-core.gemspec?ref=sha"
          ).with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "gemspec_content.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches gemspec from path dependency" do
          expect(file_fetcher_instance.files.count).to eq(3)
          expect(file_fetcher_instance.files.map(&:name)).
            to include("plugins/bump-core/bump-core/bump-core.gemspec")
        end
      end

      context "that is a submodule" do
        before do
          submodule_details =
            fixture("github", "submodule.json").
            gsub("d70e943e00a09a3c98c0e4ac9daab112b749cf62", "sha2")
          stub_request(:get, url + "plugins/bump-core?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: submodule_details,
              headers: { "content-type" => "application/json" }
            )

          sub_url = github_url + "repos/dependabot/manifesto/contents/"
          stub_request(:get, sub_url + "?ref=sha2").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "contents_ruby_path_dep_and_dir.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, sub_url + "bump-core.gemspec?ref=sha2").
            with(headers: { "Authorization" => "token token" }).
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

      context "without a Gemfile.lock" do
        before do
          stub_request(:get, url + "?ref=sha").
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "contents_ruby_no_lockfile.json"),
              headers: { "content-type" => "application/json" }
            )
        end

        it "fetches gemspec from path dependency" do
          expect(file_fetcher_instance.files.count).to eq(2)
          expect(file_fetcher_instance.files.map(&:name)).
            to include("plugins/bump-core/bump-core.gemspec")
        end
      end
    end

    context "that has no gemspecs in the path" do
      before do
        stub_request(:get, url + "plugins/bump-core?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: "[]",
            headers: { "content-type" => "application/json" }
          )
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

    context "that has an unfetchable directory path" do
      before do
        stub_request(:get, url + "plugins/bump-core?ref=sha").
          with(headers: { "Authorization" => "token token" }).
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

    context "that has a merge conflict" do
      before do
        stub_request(:get, url + "Gemfile.lock?ref=sha").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "gemfile_lock_with_merge_conflict.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "raises a DependencyFileNotParseable error with details" do
        expect { file_fetcher_instance.files }.to raise_error do |error|
          expect(error).to be_a(Dependabot::DependencyFileNotParseable)
          expect(error.file_path).to eq("/Gemfile.lock")
        end
      end
    end
  end

  context "with a child Gemfile" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "business_files_no_gemspec.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemfile_with_eval_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
    end

    context "that uses a variable name" do
      before do
        stub_request(:get, url + "Gemfile?ref=sha").
          with(headers: { "Authorization" => "token token" }).
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
          with(headers: { "Authorization" => "token token" }).
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
            with(headers: { "Authorization" => "token token" }).
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
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "gemfile_with_eval_content.json"),
              headers: { "content-type" => "application/json" }
            )
          stub_request(:get, url + "backend/backend/Gemfile?ref=sha").
            with(headers: { "Authorization" => "token token" }).
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
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_ruby_library_locked.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemfile_with_gemspec_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemfile_lock_with_gemspec_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "business.gemspec?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemspec_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches gemspec" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name)).
        to include("business.gemspec")
    end
  end

  context "with only a gemspec and a Gemfile" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_ruby_library.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemfile_with_gemspec_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "business.gemspec?ref=sha").
        with(headers: { "Authorization" => "token token" }).
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

  context "with multiple gemspecs" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_ruby_multiple_gemspecs.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemfile_with_gemspec_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "business.gemspec?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemspec_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "another.gemspec?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemspec_content.json"),
          headers: { "content-type" => "application/json" }
        )
    end

    it "fetches gemspecs" do
      expect(file_fetcher_instance.files.count).to eq(3)
      expect(file_fetcher_instance.files.map(&:name)).
        to include("business.gemspec")
      expect(file_fetcher_instance.files.map(&:name)).
        to include("another.gemspec")
    end
  end

  context "with only a gemspec" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_ruby_library_no_gemfile.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "business.gemspec?ref=sha").
        with(headers: { "Authorization" => "token token" }).
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
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "business_files_no_gemspec.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "gemfile_content.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)
    end

    it "fetches the Gemfile" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to include("Gemfile")
    end
  end

  context "with only a Gemfile.lock" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "business_files_no_gemspec.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, url + "Gemfile?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(status: 404)

      stub_request(:get, url + "Gemfile.lock?ref=sha").
        with(headers: { "Authorization" => "token token" }).
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
