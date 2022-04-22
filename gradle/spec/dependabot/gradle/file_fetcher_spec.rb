# frozen_string_literal: true

require "spec_helper"
require "dependabot/gradle/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Gradle::FileFetcher do
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
  def stub_content_request(path, fixture)
    stub_request(:get, File.join(url, path)).
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 200,
        body: fixture("github", fixture),
        headers: { "content-type" => "application/json" }
      )
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

  context "with a basic buildfile" do
    before do
      stub_content_request("?ref=sha", "contents_java.json")
      stub_content_request("build.gradle?ref=sha", "contents_java_basic_buildfile.json")
    end

    it "fetches the buildfile" do
      expect(file_fetcher_instance.files.count).to eq(1)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(build.gradle))
    end

    context "with a settings.gradle" do
      before do
        stub_content_request("?ref=sha", "contents_java_with_settings.json")
        stub_content_request("settings.gradle?ref=sha", "contents_java_simple_settings.json")
        stub_content_request("app/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
      end

      it "fetches the main buildfile and subproject buildfile" do
        expect(file_fetcher_instance.files.count).to eq(3)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(build.gradle settings.gradle app/build.gradle))
      end

      context "when the subproject can't be found" do
        before do
          stub_request(:get, File.join(url, "app/build.gradle?ref=sha")).
            with(headers: { "Authorization" => "token token" }).
            to_return(status: 404)
        end

        it "fetches the main buildfile" do
          expect(file_fetcher_instance.files.count).to eq(2)
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(build.gradle settings.gradle))
        end
      end
    end

    context "with included builds" do

      context "when has buildSrc" do
        before do
          stub_content_request("buildSrc?ref=sha", "contents_java.json")
          stub_content_request("buildSrc/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
        end

        context "implicitly included" do
          before do
            stub_content_request("?ref=sha", "contents_java_with_buildsrc.json")
          end

          it "fetches all buildfiles" do
            expect(file_fetcher_instance.files.map(&:name)).
              to match_array(%w(build.gradle buildSrc/build.gradle))
          end
        end

        context "explicitly included" do
          before do
            stub_content_request("?ref=sha", "contents_java_with_buildsrc_and_settings.json")
            stub_content_request("settings.gradle?ref=sha", "contents_java_settings_explicit_buildsrc.json")
            stub_content_request("included?ref=sha", "contents_java.json")
            stub_content_request("included/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          end

          it "doesn't fetch buildSrc buildfiles twice" do
            expect(file_fetcher_instance.files.map(&:name)).
              to match_array(%w(
                build.gradle settings.gradle
                buildSrc/build.gradle
                included/build.gradle
              ))
          end
        end
      end

      context "when only one" do
        before do
          stub_content_request("?ref=sha", "contents_java_with_settings.json")
          stub_content_request("settings.gradle?ref=sha", "contents_java_settings_1_included_build.json")
          stub_content_request("build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("app/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("included?ref=sha", "contents_java_with_settings.json")
          stub_content_request("included/settings.gradle?ref=sha", "contents_java_simple_settings.json")
          stub_content_request("included/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("included/app/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
        end

        it "fetches all buildfiles" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(
              build.gradle settings.gradle
              app/build.gradle
              included/build.gradle included/settings.gradle
              included/app/build.gradle
            ))
        end
      end

      context "when multiple" do
        before do
          stub_content_request("?ref=sha", "contents_java_with_settings.json")
          stub_content_request("settings.gradle?ref=sha", "contents_java_settings_2_included_builds.json")
          stub_content_request("build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("app/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("included?ref=sha", "contents_java_with_settings.json")
          stub_content_request("included/settings.gradle?ref=sha", "contents_java_simple_settings.json")
          stub_content_request("included/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("included/app/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("included2?ref=sha", "contents_java_with_settings.json")
          stub_content_request("included2/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("included2/settings.gradle?ref=sha", "contents_java_simple_settings.json")
          stub_content_request("included2/app/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
        end

        it "fetches all buildfiles" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(
              build.gradle settings.gradle
              app/build.gradle
              included/build.gradle included/settings.gradle
              included/app/build.gradle
              included2/build.gradle included2/settings.gradle
              included2/app/build.gradle
            ))
        end
      end

      context "when nested included builds" do
        before do
          stub_content_request("?ref=sha", "contents_java_with_settings.json")
          stub_content_request("settings.gradle?ref=sha", "contents_java_settings_1_included_build.json")
          stub_content_request("build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("app/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("included?ref=sha", "contents_java_with_settings.json")
          stub_content_request("included/settings.gradle?ref=sha", "contents_java_settings_1_included_build.json")
          stub_content_request("included/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("included/app/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("included/included?ref=sha", "contents_java_with_settings.json")
          stub_content_request("included/included/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("included/included/settings.gradle?ref=sha", "contents_java_settings_1_included_build.json")
          stub_content_request("included/included/app/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("included/included/included?ref=sha", "contents_java_with_buildsrc.json")
          stub_content_request("included/included/included/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("included/included/included/buildSrc?ref=sha", "contents_java.json")
          stub_content_request("included/included/included/buildSrc/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
        end

        it "fetches all buildfiles transitively" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(
              build.gradle settings.gradle
              app/build.gradle
              included/build.gradle included/settings.gradle
              included/app/build.gradle
              included/included/build.gradle included/included/settings.gradle
              included/included/app/build.gradle
              included/included/included/build.gradle
              included/included/included/buildSrc/build.gradle
            ))
        end
      end

      context "containing a script plugin" do
        before do
          stub_content_request("?ref=sha", "contents_java_with_settings.json")
          stub_content_request("settings.gradle?ref=sha", "contents_java_settings_1_included_build.json")
          stub_content_request("build.gradle?ref=sha", "contents_java_buildfile_with_script_plugins.json")
          stub_content_request("gradle/dependencies.gradle?ref=sha", "contents_java_simple_settings.json")
          stub_content_request("app/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
          stub_content_request("included?ref=sha", "contents_java.json")
          stub_content_request("included/build.gradle?ref=sha", "contents_java_buildfile_with_script_plugins.json")
          stub_content_request("included/gradle/dependencies.gradle?ref=sha", "contents_java_simple_settings.json")
        end

        it "fetches script plugin of main and included build" do
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(
              settings.gradle build.gradle
              app/build.gradle
              gradle/dependencies.gradle
              included/build.gradle
              included/gradle/dependencies.gradle
            ))
        end
      end
    end

    context "only a settings.gradle" do
      before do
        stub_content_request("?ref=sha", "contents_java_only_settings.json")
        stub_content_request("app?ref=sha", "contents_java_subproject.json")
        stub_content_request("settings.gradle?ref=sha", "contents_java_simple_settings.json")
        stub_content_request("app/build.gradle?ref=sha", "contents_java_basic_buildfile.json")
      end

      it "fetches the main buildfile and subproject buildfile" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(settings.gradle app/build.gradle))
      end
    end

    context "with kotlin" do
      before do
        stub_content_request("?ref=sha", "contents_kotlin.json")
        stub_content_request("build.gradle.kts?ref=sha", "contents_kotlin_basic_buildfile.json")
        stub_request(:get, File.join(url, "settings.gradle.kts?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(status: 404)
      end

      it "fetches the buildfile" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(build.gradle.kts))
      end

      context "with a settings.gradle.kts" do
        before do
          stub_content_request("?ref=sha", "contents_kotlin_with_settings.json")
          stub_content_request("settings.gradle.kts?ref=sha", "contents_kotlin_simple_settings.json")
          stub_content_request("app/build.gradle.kts?ref=sha", "contents_kotlin_basic_buildfile.json")
        end

        it "fetches the main buildfile and subproject buildfile" do
          expect(file_fetcher_instance.files.count).to eq(3)
          expect(file_fetcher_instance.files.map(&:name)).
            to match_array(%w(build.gradle.kts settings.gradle.kts app/build.gradle.kts))
        end
      end
    end
  end

  context "with a script plugin" do
    before do
      stub_content_request("?ref=sha", "contents_java.json")
      stub_content_request("build.gradle?ref=sha", "contents_java_buildfile_with_script_plugins.json")
      stub_content_request("gradle/dependencies.gradle?ref=sha", "contents_java_simple_settings.json")
    end

    it "fetches the buildfile and the dependencies script" do
      expect(file_fetcher_instance.files.count).to eq(2)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(%w(build.gradle gradle/dependencies.gradle))
    end

    context "that can't be found" do
      before do
        stub_content_request("?ref=sha", "contents_java.json")
        stub_request(
          :get,
          File.join(url, "gradle/dependencies.gradle?ref=sha")
        ).with(headers: { "Authorization" => "token token" }).
          to_return(status: 404)

        stub_content_request("gradle?ref=sha", "contents_with_settings.json")
      end

      it "raises a DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }.
          to raise_error(Dependabot::DependencyFileNotFound)
      end
    end
  end

  context "with no required manifest files" do
    before do
      stub_request(:get, url + "?ref=sha").
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: "[]",
          headers: { "content-type" => "application/json" }
        )
    end

    it "raises dependency file not found" do
      expect { file_fetcher_instance.files }.to raise_error do |error|
        expect(error).to be_a(Dependabot::DependencyFileNotFound)
        expect(error.file_path).to eq("/build.gradle(.kts)?")
      end
    end
  end
end
