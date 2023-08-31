# frozen_string_literal: true

require "spec_helper"
require "dependabot/maven/file_fetcher"
require_common_spec "file_fetchers/shared_examples_for_file_fetchers"

RSpec.describe Dependabot::Maven::FileFetcher do
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

  describe ".required_files_in?" do
    subject { described_class.required_files_in?(filenames) }

    context "with only a pom.xml" do
      let(:filenames) { %w(pom.xml) }
      it { is_expected.to eq(true) }
    end

    context "with pom.xml and any other valid .xml" do
      let(:filenames) { %w(pom.xml othermodule.xml) }
      it { is_expected.to eq(true) }
    end

    context "with only an extensions.xml" do
      let(:filenames) { %w(extensions.xml) }
      it { is_expected.to eq(false) }
    end

    context "with an extensions.xml and a valid pom.xml file" do
      let(:filenames) { %w(extensions.xml pom.xml) }
      it { is_expected.to eq(true) }
    end

    context "with a non .xml file" do
      let(:filenames) { %w(nonxml.txt) }
      it { is_expected.to eq(false) }
    end

    context "with no files passed" do
      let(:filenames) { %w() }
      it { is_expected.to eq(false) }
    end
  end

  before do
    allow(file_fetcher_instance).to receive(:commit).and_return("sha")

    stub_request(:get, File.join(url, ".mvn?ref=sha")).
      with(headers: { "Authorization" => "token token" }).
      to_return(
        status: 404
      )
  end

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

    context "without extensions.xml" do
      before do
        stub_request(:get, File.join(url, ".mvn/extensions.xml?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 404
          )
      end

      it "only fetches the pom.xml" do
        expect(file_fetcher_instance.files.count).to eq(1)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(pom.xml))
      end
    end

    context "with extensions.xml" do
      before do
        stub_request(:get, File.join(url, ".mvn?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_mvn_directory.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, File.join(url, ".mvn/extensions.xml?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_java_extensions_xml.json"),
            headers: { "content-type" => "application/json" }
          )
      end

      it "fetches the pom.xml and extensions.xml" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(pom.xml .mvn/extensions.xml))
      end
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

      stub_request(:get, File.join(url, ".mvn/extensions.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404
        )
    end

    it "fetches the poms" do
      expect(file_fetcher_instance.files.count).to eq(4)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(
          %w(pom.xml util/pom.xml business-app/pom.xml legacy/pom.xml)
        )
    end

    context "that uses submodules" do
      before do
        stub_request(:get, File.join(url, "util/pom.xml?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 404,
            headers: { "content-type" => "application/json" }
          )

        submodule_details =
          fixture("github", "submodule.json").
          gsub("d70e943e00a09a3c98c0e4ac9daab112b749cf62", "sha2")
        stub_request(:get, File.join(url, "util?ref=sha")).
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
        stub_request(:get, sub_url + "pom.xml?ref=sha2").
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 200,
            body: fixture("github", "contents_java_basic_pom.json"),
            headers: { "content-type" => "application/json" }
          )
        stub_request(:get, File.join(url, ".mvn/extensions.xml?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 404
          )
      end

      it "doesn't fetch the submodule pom (which we couldn't update)" do
        expect(file_fetcher_instance.files.count).to eq(3)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(
            %w(pom.xml business-app/pom.xml legacy/pom.xml)
          )
      end
    end

    context "where the repo for a child module is missing" do
      before do
        stub_request(:get, File.join(url, "util/pom.xml?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 404,
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, File.join(url, "util?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 404,
            headers: { "content-type" => "application/json" }
          )

        stub_request(:get, File.join(url, ".mvn/extensions.xml?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 404
          )
      end

      it "raises a Dependabot::DependencyFileNotFound error" do
        expect { file_fetcher_instance.files }.
          to raise_error(Dependabot::DependencyFileNotFound) do |error|
            expect(error.file_path).to eq("/util/pom.xml")
          end
      end
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

        stub_request(:get, File.join(url, ".mvn/extensions.xml?ref=sha")).
          with(headers: { "Authorization" => "token token" }).
          to_return(
            status: 404
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
        before do
          stub_request(:get, File.join(url, "util/util/.mvn?ref=sha")).
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 404
            )
          stub_request(:get, File.join(url, "util/util/.mvn/extensions.xml?ref=sha")).
            with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 404
            )
        end
        let(:directory) { "/util/util" }

        it "fetches the relevant pom" do
          expect(file_fetcher_instance.files.map(&:name)).to eq(%w(pom.xml))
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

  context "with a multimodule custom named child poms" do
    before do
      stub_request(:get, File.join(url, "pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_java_multimodule_different_pom_names.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "submodule-one/pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_java_basic_pom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "submodule-three/some-other-name.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_java_basic_pom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "submodule-two/notpom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_java_basic_pom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, ".mvn/extensions.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404
        )
    end

    it "fetches the child poms with different names" do
      expect(file_fetcher_instance.files.count).to eq(4)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(
          %w(pom.xml submodule-one/pom.xml submodule-three/some-other-name.xml submodule-two/notpom.xml)
        )
    end
  end

  context "with a parent pom with custom name" do
    before do
      stub_request(:get, File.join(url, "pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_java_parent_pom_custom_name.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "parentpom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "contents_java_parent_pom_custom_name_parent.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, ".mvn/extensions.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404
        )
    end

    it "fetches the parent pom" do
      expect(file_fetcher_instance.files.count).to eq(2)
      expect(file_fetcher_instance.files.map(&:name)).
        to match_array(
          %w(pom.xml parentpom.xml)
        )
    end
  end

  context "with a project with multiple related and unrelated maven modules inside" do
    before do
      stub_request(:get, File.join(url, "parent_modules_project/pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "parent_modules_root_pom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get,
                   File.join(url, "parent_modules_project/pom_with_parent_groupid/pom_with_parent/pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "parent_modules_pom_with_parent.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "parent_modules_project/pom_with_parent_groupid/pom_parent.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "parent_modules_parent_of_pom_with_parent.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "parent_modules_project/pom_with_no_parent/pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "parent_modules_no_parent_pom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "parent_modules_project/pom_with_implicit_parent_path/pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "parent_modules_implicit_parent_pom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "parent_modules_project/different_version/pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "parent_modules_different_version_pom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "parent_modules_project/different_group_id/pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "parent_modules_different_group_pom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "parent_modules_project/different_artifact_id/pom.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 200,
          body: fixture("github", "parent_modules_different_artifact_pom.json"),
          headers: { "content-type" => "application/json" }
        )

      stub_request(:get, File.join(url, "parent_modules_project/pom_with_parent_groupid/pom_with_parent/.mvn?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404
        )

      stub_request(:get, File.join(url, "parent_modules_project/pom_with_no_parent/.mvn?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404
        )

      stub_request(:get, File.join(url, "parent_modules_project/pom_with_implicit_parent_path/.mvn?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404
        )

      stub_request(:get, File.join(url, "parent_modules_project/different_version/.mvn?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404
        )

      stub_request(:get, File.join(url, "parent_modules_project/different_group_id/.mvn?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404
        )

      stub_request(:get, File.join(url, "parent_modules_project/different_artifact_id/.mvn?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404
        )

      stub_request(:get, File.join(url, ".mvn/extensions.xml?ref=sha")).
        with(headers: { "Authorization" => "token token" }).
        to_return(
          status: 404
        )
    end

    context "when asked to fetch a pom with a parent which has inherited group id" do
      let(:directory) { "/parent_modules_project/pom_with_parent_groupid/pom_with_parent" }
      it "fetches the relevant poms" do
        expect(file_fetcher_instance.files.count).to eq(3)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(pom.xml ../pom_parent.xml ../../pom.xml))
      end
    end

    context "when asked to fetch a pom with no parent defined" do
      let(:directory) { "/parent_modules_project/pom_with_no_parent" }
      it "fetches only this pom" do
        expect(file_fetcher_instance.files.map(&:name)).to eq(%w(pom.xml))
      end
    end

    context "when asked to fetch a pom with an implicit path to parent defined" do
      let(:directory) { "/parent_modules_project/pom_with_implicit_parent_path" }
      it "fetches only both this pom and its implicit parent" do
        expect(file_fetcher_instance.files.count).to eq(2)
        expect(file_fetcher_instance.files.map(&:name)).
          to match_array(%w(pom.xml ../pom.xml))
      end
    end

    context "when asked to fetch a pom which local parent has different version" do
      let(:directory) { "/parent_modules_project/different_version" }
      it "fetches only this pom" do
        expect(file_fetcher_instance.files.map(&:name)).to eq(%w(pom.xml))
      end
    end

    context "when asked to fetch a pom which local parent has different groupId" do
      let(:directory) { "/parent_modules_project/different_group_id" }
      it "fetches only this pom" do
        expect(file_fetcher_instance.files.map(&:name)).to eq(%w(pom.xml))
      end
    end

    context "when asked to fetch a pom which local parent has different artifactId" do
      let(:directory) { "/parent_modules_project/different_artifact_id" }
      it "fetches only this pom" do
        expect(file_fetcher_instance.files.map(&:name)).to eq(%w(pom.xml))
      end
    end
  end
end
