# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/source"
require "dependabot/pull_request_creator/labeler"

RSpec.describe Dependabot::PullRequestCreator::Labeler do
  subject(:labeler) do
    described_class.new(
      source: source,
      credentials: credentials,
      custom_labels: custom_labels,
      includes_security_fixes: includes_security_fixes,
      dependencies: [dependency],
      label_language: label_language,
      automerge_candidate: automerge_candidate
    )
  end

  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
  end
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:custom_labels) { nil }
  let(:includes_security_fixes) { false }
  let(:label_language) { false }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: version,
      previous_version: previous_version,
      package_manager: "dummy",
      requirements: requirements,
      previous_requirements: previous_requirements
    )
  end
  let(:automerge_candidate) { false }

  let(:version) { "1.5.0" }
  let(:previous_version) { "1.4.0" }
  let(:requirements) do
    [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }]
  end
  let(:previous_requirements) do
    [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:repo_api_url) { "https://api.github.com/repos/#{source.repo}" }

  describe ".package_manager_labels" do
    subject { described_class.package_manager_labels }

    it { is_expected.to eq("dummy" => { colour: "ce2d2d", name: "ruby" }) }
  end

  describe "#create_default_labels_if_required" do
    subject { labeler.create_default_labels_if_required }

    context "with GitHub details" do
      let(:source) do
        Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
      end
      let(:labels_fixture_name) { "labels_with_dependencies.json" }
      let(:repo_api_url) { "https://api.github.com/repos/#{source.repo}" }

      before do
        stub_request(:get, "#{repo_api_url}/labels?per_page=100")
          .to_return(status: 200,
                     body: fixture("github", labels_fixture_name),
                     headers: json_header)
      end

      context "when the 'dependencies' label doesn't yet exist" do
        let(:labels_fixture_name) { "labels_without_dependencies.json" }

        before do
          stub_request(:post, "#{repo_api_url}/labels")
            .to_return(status: 201,
                       body: fixture("github", "create_label.json"),
                       headers: json_header)
        end

        it "creates a 'dependencies' label" do
          labeler.create_default_labels_if_required

          expect(WebMock)
            .to have_requested(:post, "#{repo_api_url}/labels")
            .with(
              body: {
                name: "dependencies",
                color: "0366d6",
                description: "Pull requests that update a dependency file"
              }
            )
          expect(labeler.labels_for_pr).to include("dependencies")
        end

        context "when there's a race and we lose" do
          before do
            stub_request(:post, "#{repo_api_url}/labels")
              .to_return(status: 422,
                         body: fixture("github", "label_already_exists.json"),
                         headers: json_header)
          end

          it "quietly ignores losing the race" do
            expect { labeler.create_default_labels_if_required }
              .not_to raise_error
            expect(labeler.labels_for_pr).to include("dependencies")
          end
        end
      end

      context "when there is a custom dependencies label" do
        let(:labels_fixture_name) { "labels_with_custom.json" }

        it "does not create a 'dependencies' label" do
          labeler.create_default_labels_if_required

          expect(WebMock)
            .not_to have_requested(:post, "#{repo_api_url}/labels")
        end

        context "when dealing with the label that is only present after paginating" do
          let(:repo_labels_url) { "#{repo_api_url}/labels?per_page=100" }
          let(:links_header) do
            {
              "Content-Type" => "application/json",
              "Link" => "<#{repo_labels_url}&page=2>; rel=\"next\", " \
                        "<#{repo_labels_url}&page=3>; rel=\"last\""
            }
          end

          before do
            stub_request(:get, repo_labels_url)
              .to_return(
                status: 200,
                body: fixture("github", "labels_without_dependencies.json"),
                headers: links_header
              )
            stub_request(:get, repo_labels_url + "&page=2")
              .to_return(
                status: 200,
                body: fixture("github", "labels_with_custom.json"),
                headers: json_header
              )
          end

          it "does not create a 'dependencies' label" do
            labeler.create_default_labels_if_required

            expect(WebMock)
              .not_to have_requested(:post, "#{repo_api_url}/labels")
          end
        end

        context "when considering the label that should be ignored" do
          let(:labels_fixture_name) { "labels_with_custom_ignored.json" }

          before do
            stub_request(:post, "#{repo_api_url}/labels")
              .to_return(
                status: 201,
                body: fixture("github", "create_label.json"),
                headers: json_header
              )
          end

          it "creates a 'dependencies' label" do
            labeler.create_default_labels_if_required

            expect(WebMock)
              .to have_requested(:post, "#{repo_api_url}/labels")
              .with(
                body: {
                  name: "dependencies",
                  color: "0366d6",
                  description: "Pull requests that update a dependency file"
                }
              )
            expect(labeler.labels_for_pr).to include("dependencies")
          end
        end
      end

      context "when label_language is true" do
        let(:label_language) { true }

        context "when the 'ruby' label doesn't yet exist" do
          let(:labels_fixture_name) { "labels_with_dependencies.json" }

          before do
            stub_request(:post, "#{repo_api_url}/labels")
              .to_return(status: 201,
                         body: fixture("github", "create_label.json"),
                         headers: json_header)
          end

          it "creates a 'ruby' label" do
            labeler.create_default_labels_if_required

            expect(WebMock)
              .to have_requested(:post, "#{repo_api_url}/labels")
              .with(
                body: {
                  name: "ruby",
                  color: "ce2d2d",
                  description: "Pull requests that update Ruby code"
                }
              )
            expect(labeler.labels_for_pr).to include("dependencies")
          end
        end

        context "when the 'ruby' label already exists" do
          let(:labels_fixture_name) { "labels_with_language.json" }

          it "does not create a 'ruby' label" do
            labeler.create_default_labels_if_required

            expect(WebMock)
              .not_to have_requested(:post, "#{repo_api_url}/labels")
          end
        end

        context "when the 'github_actions' label doesn't yet exist" do
          before do
            allow(described_class).to receive(:label_details_for_package_manager)
              .with("github_actions")
              .and_return({
                colour: "000000",
                name: "github_actions",
                description: "Pull requests that update GitHub Actions code"
              })
            allow(dependency).to receive(:package_manager).and_return("github_actions")

            stub_request(:get, "https://api.github.com/repos/#{source.repo}/labels?per_page=100")
              .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate([]))
            stub_request(:post, "https://api.github.com/repos/#{source.repo}/labels")
              .to_return(
                status: 201,
                headers: { "Content-Type" => "application/json" },
                body: JSON.generate({ id: 1, name: "github_actions", color: "000000" })
              )
          end

          it "creates a label" do
            labeler.create_default_labels_if_required

            expect(WebMock).to have_requested(:post, "https://api.github.com/repos/#{source.repo}/labels")
              .with(body: {
                name: "github_actions",
                color: "000000",
                description: "Pull requests that update GitHub Actions code"
              })
          end
        end
      end

      context "when a custom dependencies label has been requested" do
        let(:custom_labels) { ["wontfix"] }

        it "does not create a 'dependencies' label" do
          labeler.create_default_labels_if_required
          expect(WebMock).not_to have_requested(:post, "#{repo_api_url}/labels")
        end

        context "when label_language is true" do
          let(:label_language) { true }

          it "does not create a 'ruby' label" do
            labeler.create_default_labels_if_required

            expect(WebMock)
              .not_to have_requested(:post, "#{repo_api_url}/labels")
          end
        end

        context "when the label is not exist" do
          let(:custom_labels) { ["non-existent"] }

          it "does not create any labels" do
            labeler.create_default_labels_if_required

            expect(WebMock)
              .not_to have_requested(:post, "#{repo_api_url}/labels")
          end
        end
      end

      context "when applying an update that fixes a security vulnerability" do
        let(:includes_security_fixes) { true }

        context "when the 'security' label doesn't yet exist" do
          before do
            stub_request(:post, "#{repo_api_url}/labels")
              .to_return(status: 201,
                         body: fixture("github", "create_label.json"),
                         headers: json_header)
          end

          it "creates a 'security' label" do
            labeler.create_default_labels_if_required

            expect(WebMock)
              .to have_requested(:post, "#{repo_api_url}/labels")
              .with(
                body: {
                  name: "security",
                  color: "ee0701",
                  description: "Pull requests that address a security " \
                               "vulnerability"
                }
              )
            expect(labeler.labels_for_pr).to include("security")
          end
        end

        context "when a 'security' label already exist" do
          let(:labels_fixture_name) { "labels_with_security.json" }

          it "does not creates a 'security' label" do
            labeler.create_default_labels_if_required

            expect(WebMock)
              .not_to have_requested(:post, "#{repo_api_url}/labels")
            expect(labeler.labels_for_pr).to include("security")
          end
        end
      end
    end

    context "with Azure details" do
      let(:source) do
        Dependabot::Source.new(provider: "azure", repo: "gocardless/bump")
      end

      context "when the 'dependencies' label doesn't yet exist" do
        it "creates a 'dependencies' label" do
          labeler.create_default_labels_if_required

          expect(labeler.labels_for_pr).to include("dependencies")
        end
      end

      context "when applying an update that fixes a security vulnerability" do
        let(:includes_security_fixes) { true }

        context "when the 'security' label doesn't yet exist" do
          it "creates a 'security' label" do
            labeler.create_default_labels_if_required

            expect(labeler.labels_for_pr).to include("security")
          end
        end

        context "when a 'security' label already exist" do
          it "does not creates a 'security' label" do
            labeler.create_default_labels_if_required

            expect(labeler.labels_for_pr).to include("security")
          end
        end
      end
    end

    context "with GitLab details" do
      let(:source) do
        Dependabot::Source.new(provider: "gitlab", repo: "gocardless/bump")
      end
      let(:repo_api_url) do
        "https://gitlab.com/api/v4/projects/#{CGI.escape(source.repo)}"
      end

      before do
        stub_request(:get, "#{repo_api_url}/labels?per_page=100")
          .to_return(status: 200,
                     body: fixture("gitlab", "labels_with_dependencies.json"),
                     headers: json_header)
      end

      context "when the 'dependencies' label doesn't yet exist" do
        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100")
            .to_return(
              status: 200,
              body: fixture("gitlab", "labels_without_dependencies.json"),
              headers: json_header
            )
          stub_request(:post, "#{repo_api_url}/labels")
            .to_return(status: 201,
                       body: fixture("gitlab", "label.json"),
                       headers: json_header)
        end

        it "creates a 'dependencies' label" do
          labeler.create_default_labels_if_required

          expect(WebMock)
            .to have_requested(:post, "#{repo_api_url}/labels")
            .with(
              body: "description=Pull%20requests%20that%20update%20a" \
                    "%20dependency%20file&name=dependencies&color=%230366d6"
            )
          expect(labeler.labels_for_pr).to include("dependencies")
        end
      end

      context "when there is a custom dependencies label" do
        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100")
            .to_return(status: 200,
                       body: fixture("gitlab", "labels_with_custom.json"),
                       headers: json_header)
        end

        it "does not create a 'dependencies' label" do
          labeler.create_default_labels_if_required

          expect(WebMock)
            .not_to have_requested(:post, "#{repo_api_url}/labels")
        end
      end

      context "when a custom dependencies label has been requested" do
        let(:custom_labels) { ["wontfix"] }

        it "does not create a 'dependencies' label" do
          labeler.create_default_labels_if_required

          expect(WebMock)
            .not_to have_requested(:post, "#{repo_api_url}/labels")
        end

        context "when the label is not exist" do
          let(:custom_labels) { ["non-existent"] }

          it "does not create any labels" do
            labeler.create_default_labels_if_required

            expect(WebMock)
              .not_to have_requested(:post, "#{repo_api_url}/labels")
          end
        end
      end

      context "when applying an update that fixes a security vulnerability" do
        let(:includes_security_fixes) { true }

        context "when the 'security' label doesn't yet exist" do
          before do
            stub_request(:post, "#{repo_api_url}/labels")
              .to_return(status: 201,
                         body: fixture("gitlab", "label.json"),
                         headers: json_header)
          end

          it "creates a 'security' label" do
            labeler.create_default_labels_if_required

            expect(WebMock)
              .to have_requested(:post, "#{repo_api_url}/labels")
              .with(
                body: "description=Pull%20requests%20that%20address%20a" \
                      "%20security%20vulnerability&name=security&color=%23ee0701"
              )
            expect(labeler.labels_for_pr).to include("security")
          end
        end

        context "when a 'security' label already exist" do
          before do
            stub_request(:get, "#{repo_api_url}/labels?per_page=100")
              .to_return(status: 200,
                         body: fixture("gitlab", "labels_with_security.json"),
                         headers: json_header)
          end

          it "does not creates a 'security' label" do
            labeler.create_default_labels_if_required

            expect(WebMock)
              .not_to have_requested(:post, "#{repo_api_url}/labels")
            expect(labeler.labels_for_pr).to include("security")
          end
        end
      end
    end
  end

  describe "#labels_for_pr" do
    subject { labeler.labels_for_pr }

    context "with GitHub details" do
      let(:source) do
        Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
      end
      let(:labels_fixture_name) { "labels_with_dependencies.json" }
      let(:repo_api_url) { "https://api.github.com/repos/#{source.repo}" }

      before do
        stub_request(:get, "#{repo_api_url}/labels?per_page=100")
          .to_return(status: 200,
                     body: fixture("github", labels_fixture_name),
                     headers: json_header)
      end

      context "when a 'dependencies' label exists" do
        let(:labels_fixture_name) { "labels_with_dependencies.json" }

        it { is_expected.to eq(["dependencies"]) }

        context "when dealing with a security fix" do
          let(:includes_security_fixes) { true }
          let(:labels_fixture_name) { "labels_with_security.json" }

          it { is_expected.to eq(%w(dependencies security)) }
        end
      end

      context "when a 'ruby' label exists" do
        let(:labels_fixture_name) { "labels_with_language.json" }

        it { is_expected.to eq(["dependencies"]) }

        context "when label_language is true" do
          let(:label_language) { true }

          it { is_expected.to match_array(%w(dependencies ruby)) }
        end
      end

      context "when a custom dependencies label exists" do
        let(:labels_fixture_name) { "labels_with_custom.json" }

        it { is_expected.to eq(["Dependency: Gems"]) }
      end

      context "when a default and custom dependencies label exists" do
        let(:labels_fixture_name) { "labels_with_custom_and_default.json" }

        it { is_expected.to eq(["dependencies"]) }
      end

      context "when asking for custom labels" do
        let(:custom_labels) { ["wontfix"] }

        it { is_expected.to eq(["wontfix"]) }

        context "when the label is not exist" do
          let(:custom_labels) { ["non-existent"] }

          it { is_expected.to eq([]) }
        end

        context "when only one doesn't exist" do
          let(:custom_labels) { %w(wontfix non-existent) }

          it { is_expected.to eq(["wontfix"]) }
        end
      end

      context "when dealing with an automerge candidate" do
        let(:automerge_candidate) { true }

        it { is_expected.not_to include("automerge") }

        context "when dealing with a repo that has an automerge label" do
          let(:labels_fixture_name) { "labels_with_automerge_tag.json" }

          it { is_expected.to include("automerge") }
        end
      end

      context "when dealing with a non-automerge candidate" do
        let(:automerge_candidate) { false }

        context "when dealing with a repo that has an automerge label" do
          let(:labels_fixture_name) { "labels_with_automerge_tag.json" }

          it { is_expected.not_to include("automerge") }
        end
      end

      context "when dealing with a repo without patch, minor and major labels" do
        it { is_expected.not_to include("patch") }
      end

      context "when dealing with a repo that has patch, minor and major labels" do
        let(:labels_fixture_name) { "labels_with_semver_tags.json" }

        context "with a version and a previous version" do
          let(:previous_version) { "1.4.0" }

          context "when dealing with a patch release" do
            let(:version) { "1.4.1" }

            it { is_expected.to include("patch") }

            context "when the tags are for an auto-releasing tool" do
              let(:labels_fixture_name) { "labels_with_semver_tags_auto.json" }

              it { is_expected.not_to include("patch") }
            end
          end

          context "when dealing with a patch release with build identifier" do
            let(:version) { "1.4.1+10" }

            it { is_expected.to include("patch") }

            context "when the tags are for an auto-releasing tool" do
              let(:labels_fixture_name) { "labels_with_semver_tags_auto.json" }

              it { is_expected.not_to include("patch") }
            end
          end

          context "when dealing with a patch release and both have build identifiers" do
            let(:previous_version) { "1.4.0+10" }
            let(:version) { "1.4.1+9" }

            it { is_expected.to include("patch") }

            context "when the tags are for an auto-releasing tool" do
              let(:labels_fixture_name) { "labels_with_semver_tags_auto.json" }

              it { is_expected.not_to include("patch") }
            end
          end

          context "when dealing with a minor release" do
            let(:version) { "1.5.1" }

            it { is_expected.to include("minor") }
          end

          context "when dealing with a minor release with build identifier" do
            let(:version) { "1.5.1+1" }

            it { is_expected.to include("minor") }
          end

          context "when dealing with a minor release when both have build identifiers" do
            let(:previous_version) { "1.4.0+10" }
            let(:version) { "1.5.1+1" }

            it { is_expected.to include("minor") }
          end

          context "when dealing with a major release" do
            let(:version) { "2.5.1" }

            it { is_expected.to include("major") }
          end

          context "when dealing with a major release with build identifier" do
            let(:version) { "2.5.1+100" }

            it { is_expected.to include("major") }
          end

          context "when dealing with a major release and both have build identifiers" do
            let(:previous_version) { "1.4.0+10" }
            let(:version) { "2.5.1+100" }

            it { is_expected.to include("major") }
          end

          context "when dealing with a non-semver release" do
            let(:version) { "random" }

            it { is_expected.to eq(["dependencies"]) }
          end

          context "when dealing with a git dependency" do
            let(:version) { "6cf3d8c20aa5171b4f9f98ab8f4b6ced5ace912f" }
            let(:previous_version) do
              "9cd93a80d534ff616458af949b0d67aa10812d1a"
            end
            let(:requirements) do
              [{
                file: "Gemfile",
                requirement: "~> 1.5.0",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/gocardless/business",
                  branch: "master",
                  ref: "v1.5.0"
                }
              }]
            end
            let(:previous_requirements) do
              [{
                file: "Gemfile",
                requirement: "~> 1.4.0",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/gocardless/business",
                  branch: "master",
                  ref: "v1.4.0"
                }
              }]
            end

            it { is_expected.to include("minor") }
          end
        end

        context "without a previous version" do
          let(:previous_version) { nil }

          it { is_expected.to eq(["dependencies"]) }
        end
      end

      context "when applying an update that fixes a security vulnerability" do
        let(:includes_security_fixes) { true }

        context "when a default and custom dependencies label exists" do
          let(:labels_fixture_name) do
            "labels_with_security_with_custom_and_default.json"
          end

          it { is_expected.to eq(%w(dependencies security)) }
        end
      end
    end

    context "with Azure details" do
      let(:source) do
        Dependabot::Source.new(provider: "azure", repo: "gocardless/bump")
      end

      context "when a 'dependencies' label exists" do
        it { is_expected.to eq(["dependencies"]) }

        context "when applying a security fix" do
          let(:includes_security_fixes) { true }

          it { is_expected.to eq(%w(dependencies security)) }
        end
      end

      context "when a custom dependencies label exists" do
        it { is_expected.to eq(["dependencies"]) }
      end

      context "when asking for custom labels" do
        let(:custom_labels) { ["critical"] }

        it { is_expected.to eq(["critical"]) }

        context "when dealing with the labels that don't exist" do
          let(:custom_labels) { ["non-existent"] }

          it { is_expected.to eq(["non-existent"]) }
        end

        context "when only one doesn't exist" do
          let(:custom_labels) { %w(critical non-existent) }

          it { is_expected.to eq(%w(critical non-existent)) }
        end
      end
    end

    context "with GitLab details" do
      let(:source) do
        Dependabot::Source.new(provider: "gitlab", repo: "gocardless/bump")
      end
      let(:repo_api_url) do
        "https://gitlab.com/api/v4/projects/#{CGI.escape(source.repo)}"
      end

      before do
        stub_request(:get, "#{repo_api_url}/labels?per_page=100")
          .to_return(status: 200,
                     body: fixture("gitlab", "labels_with_dependencies.json"),
                     headers: json_header)
      end

      context "when a 'dependencies' label exists" do
        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100")
            .to_return(status: 200,
                       body: fixture("gitlab", "labels_with_dependencies.json"),
                       headers: json_header)
        end

        it { is_expected.to eq(["dependencies"]) }

        context "when dealing with a security fix" do
          let(:includes_security_fixes) { true }

          before do
            stub_request(:get, "#{repo_api_url}/labels?per_page=100")
              .to_return(status: 200,
                         body: fixture("github", "labels_with_security.json"),
                         headers: json_header)
          end

          it { is_expected.to eq(%w(dependencies security)) }
        end
      end

      context "when a custom dependencies label exists" do
        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100")
            .to_return(status: 200,
                       body: fixture("gitlab", "labels_with_custom.json"),
                       headers: json_header)
        end

        it { is_expected.to eq(["Dependency: Gems"]) }
      end

      context "when pagination is required" do
        let(:pagination_header) do
          {
            "Content-Type" => "application/json",
            "Link" => "<#{repo_api_url}/labels?page=2&per_page=100>; " \
                      "rel=\"next\""
          }
        end

        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100")
            .to_return(
              status: 200,
              body: fixture("gitlab", "labels_without_dependencies.json"),
              headers: pagination_header
            )
          stub_request(:get, "#{repo_api_url}/labels?page=2&per_page=100")
            .to_return(status: 200,
                       body: fixture("gitlab", "labels_with_custom.json"),
                       headers: json_header)
        end

        it { is_expected.to eq(["Dependency: Gems"]) }
      end

      context "when asking for custom labels" do
        let(:custom_labels) { ["critical"] }

        it { is_expected.to eq(["critical"]) }

        context "when dealing with labels that don't exist" do
          let(:custom_labels) { ["non-existent"] }

          it { is_expected.to eq([]) }
        end

        context "when only one doesn't exist" do
          let(:custom_labels) { %w(critical non-existent) }

          it { is_expected.to eq(["critical"]) }
        end
      end
    end
  end

  describe "#label_pull_request" do
    subject(:label_pr) { labeler.label_pull_request(pull_request_number) }

    let(:pull_request_number) { 1 }

    context "with GitHub details" do
      let(:source) do
        Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
      end
      let(:repo_api_url) { "https://api.github.com/repos/#{source.repo}" }

      before do
        stub_request(:post, "#{repo_api_url}/issues/1/labels")
          .to_return(status: 200,
                     body: fixture("github", "create_label.json"),
                     headers: json_header)
      end

      context "when a 'dependencies' label already exists" do
        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100")
            .to_return(status: 200,
                       body: fixture("github", "labels_with_dependencies.json"),
                       headers: json_header)
        end

        it "labels the PR" do
          label_pr

          expect(WebMock)
            .to have_requested(:post, "#{repo_api_url}/issues/1/labels")
            .with(body: '["dependencies"]')
        end

        context "when GitHub unexpectedly errors" do
          before do
            stub_request(:post, "#{repo_api_url}/issues/1/labels")
              .to_return(
                status: 422,
                body: fixture("github", "label_already_exists.json"),
                headers: json_header
              ).to_return(
                status: 200,
                body: fixture("github", "labels_with_dependencies.json"),
                headers: json_header
              )
          end

          it "labels the PR" do
            label_pr

            expect(WebMock)
              .to have_requested(:post, "#{repo_api_url}/issues/1/labels")
              .with(body: '["dependencies"]')
              .twice
          end
        end

        context "when GitHub unexpectedly 404s" do
          before do
            stub_request(:post, "#{repo_api_url}/issues/1/labels")
              .to_return(status: 404)
              .to_return(
                status: 200,
                body: fixture("github", "labels_with_dependencies.json"),
                headers: json_header
              )
          end

          it "labels the PR" do
            label_pr

            expect(WebMock)
              .to have_requested(:post, "#{repo_api_url}/issues/1/labels")
              .with(body: '["dependencies"]')
              .twice
          end
        end

        context "when dealing with a security fix" do
          let(:includes_security_fixes) { true }

          before do
            stub_request(:get, "#{repo_api_url}/labels?per_page=100")
              .to_return(status: 200,
                         body: fixture("github", "labels_with_security.json"),
                         headers: json_header)
          end

          it "labels the PR" do
            label_pr

            expect(WebMock)
              .to have_requested(:post, "#{repo_api_url}/issues/1/labels")
              .with(body: '["dependencies","security"]')
          end
        end
      end

      context "when requesting custom labels that don't exist" do
        let(:custom_labels) { ["non-existent"] }

        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100")
            .to_return(status: 200,
                       body: fixture("github", "labels_with_dependencies.json"),
                       headers: json_header)
        end

        it "does not label the PR" do
          label_pr

          expect(WebMock)
            .not_to have_requested(:post, "#{repo_api_url}/issues/1/labels")
        end
      end
    end
  end
end
