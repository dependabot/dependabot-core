# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator/labeler"

RSpec.describe Dependabot::PullRequestCreator::Labeler do
  subject(:labeler) do
    described_class.new(
      source: source,
      credentials: credentials,
      custom_labels: custom_labels,
      includes_security_fixes: includes_security_fixes,
      dependencies: [dependency],
      label_language: label_language
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
      package_manager: "bundler",
      requirements: requirements,
      previous_requirements: previous_requirements
    )
  end

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

  describe "#create_default_labels_if_required" do
    subject { labeler.create_default_labels_if_required }

    context "with GitHub details" do
      let(:source) do
        Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
      end
      let(:repo_api_url) { "https://api.github.com/repos/#{source.repo}" }
      before do
        stub_request(:get, "#{repo_api_url}/labels?per_page=100").
          to_return(status: 200,
                    body: fixture("github", "labels_with_dependencies.json"),
                    headers: json_header)
      end

      context "when the 'dependencies' label doesn't yet exist" do
        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100").
            to_return(
              status: 200,
              body: fixture("github", "labels_without_dependencies.json"),
              headers: json_header
            )
          stub_request(:post, "#{repo_api_url}/labels").
            to_return(status: 201,
                      body: fixture("github", "create_label.json"),
                      headers: json_header)
        end

        it "creates a 'dependencies' label" do
          labeler.create_default_labels_if_required

          expect(WebMock).
            to have_requested(:post, "#{repo_api_url}/labels").
            with(
              body: {
                name: "dependencies",
                color: "0025ff",
                description: "Pull requests that update a dependency file"
              }
            )
          expect(labeler.labels_for_pr).to include("dependencies")
        end

        context "when there's a race and we lose" do
          before do
            stub_request(:post, "#{repo_api_url}/labels").
              to_return(status: 422,
                        body: fixture("github", "label_already_exists.json"),
                        headers: json_header)
          end

          it "quietly ignores losing the race" do
            expect { labeler.create_default_labels_if_required }.
              to_not raise_error
            expect(labeler.labels_for_pr).to include("dependencies")
          end
        end
      end

      context "when there is a custom dependencies label" do
        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100").
            to_return(status: 200,
                      body: fixture("github", "labels_with_custom.json"),
                      headers: json_header)
        end

        it "does not create a 'dependencies' label" do
          labeler.create_default_labels_if_required

          expect(WebMock).
            to_not have_requested(:post, "#{repo_api_url}/labels")
        end

        context "that should be ignored" do
          before do
            stub_request(:get, "#{repo_api_url}/labels?per_page=100").
              to_return(
                status: 200,
                body: fixture("github", "labels_with_custom_ignored.json"),
                headers: json_header
              )
            stub_request(:post, "#{repo_api_url}/labels").
              to_return(
                status: 201,
                body: fixture("github", "create_label.json"),
                headers: json_header
              )
          end

          it "creates a 'dependencies' label" do
            labeler.create_default_labels_if_required

            expect(WebMock).
              to have_requested(:post, "#{repo_api_url}/labels").
              with(
                body: {
                  name: "dependencies",
                  color: "0025ff",
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
          before do
            stub_request(:get, "#{repo_api_url}/labels?per_page=100").
              to_return(
                status: 200,
                body: fixture("github", "labels_with_dependencies.json"),
                headers: json_header
              )
            stub_request(:post, "#{repo_api_url}/labels").
              to_return(status: 201,
                        body: fixture("github", "create_label.json"),
                        headers: json_header)
          end

          it "creates a 'ruby' label" do
            labeler.create_default_labels_if_required

            expect(WebMock).
              to have_requested(:post, "#{repo_api_url}/labels").
              with(body: { name: "ruby", color: "ce2d2d" })
            expect(labeler.labels_for_pr).to include("dependencies")
          end
        end

        context "when the 'ruby' label already exists" do
          before do
            stub_request(:get, "#{repo_api_url}/labels?per_page=100").
              to_return(
                status: 200,
                body: fixture("github", "labels_with_language.json"),
                headers: json_header
              )
          end

          it "does not create a 'ruby' label" do
            labeler.create_default_labels_if_required

            expect(WebMock).
              to_not have_requested(:post, "#{repo_api_url}/labels")
          end
        end
      end

      context "when a custom dependencies label has been requested" do
        let(:custom_labels) { ["wontfix"] }

        it "does not create a 'dependencies' label" do
          labeler.create_default_labels_if_required
          expect(WebMock).to_not have_requested(:post, "#{repo_api_url}/labels")
        end

        context "when label_language is true" do
          let(:label_language) { true }

          it "does not create a 'ruby' label" do
            labeler.create_default_labels_if_required

            expect(WebMock).
              to_not have_requested(:post, "#{repo_api_url}/labels")
          end
        end

        context "that doesn't exist" do
          let(:custom_labels) { ["non-existent"] }

          it "does not create any labels" do
            labeler.create_default_labels_if_required

            expect(WebMock).
              to_not have_requested(:post, "#{repo_api_url}/labels")
          end
        end
      end

      context "for a repo without patch, minor and major labels" do
        it "does not include a patch label" do
          expect(labeler.labels_for_pr).to_not include("patch")
        end
      end

      context "for a repo that has patch, minor and major labels" do
        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100").
            to_return(status: 200,
                      body: fixture("github", "labels_with_semver_tags.json"),
                      headers: json_header)
        end
        subject { labeler.labels_for_pr }

        context "with a version and a previous version" do
          let(:previous_version) { "1.4.0" }

          context "for a patch release" do
            let(:version) { "1.4.1" }
            it { is_expected.to include("patch") }
          end

          context "for a minor release" do
            let(:version) { "1.5.1" }
            it { is_expected.to include("minor") }
          end

          context "for a major release" do
            let(:version) { "2.5.1" }
            it { is_expected.to include("major") }
          end

          context "for a non-semver release" do
            let(:version) { "random" }
            it { is_expected.to eq(["dependencies"]) }
          end
        end

        context "without a previous version" do
          let(:previous_version) { nil }
          it { is_expected.to eq(["dependencies"]) }
        end
      end

      context "for an update that fixes a security vulnerability" do
        let(:includes_security_fixes) { true }

        context "when the 'security' label doesn't yet exist" do
          before do
            stub_request(:post, "#{repo_api_url}/labels").
              to_return(status: 201,
                        body: fixture("github", "create_label.json"),
                        headers: json_header)
          end

          it "creates a 'security' label" do
            labeler.create_default_labels_if_required

            expect(WebMock).
              to have_requested(:post, "#{repo_api_url}/labels").
              with(
                body: {
                  name: "security",
                  color: "ee0701",
                  description: "Pull requests that address a security "\
                               "vulnerability"
                }
              )
            expect(labeler.labels_for_pr).to include("security")
          end
        end

        context "when a 'security' label already exist" do
          before do
            stub_request(:get, "#{repo_api_url}/labels?per_page=100").
              to_return(status: 200,
                        body: fixture("github", "labels_with_security.json"),
                        headers: json_header)
          end

          it "does not creates a 'security' label" do
            labeler.create_default_labels_if_required

            expect(WebMock).
              to_not have_requested(:post, "#{repo_api_url}/labels")
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
        stub_request(:get, "#{repo_api_url}/labels").
          to_return(status: 200,
                    body: fixture("gitlab", "labels_with_dependencies.json"),
                    headers: json_header)
      end

      context "when the 'dependencies' label doesn't yet exist" do
        before do
          stub_request(:get, "#{repo_api_url}/labels").
            to_return(
              status: 200,
              body: fixture("gitlab", "labels_without_dependencies.json"),
              headers: json_header
            )
          stub_request(:post, "#{repo_api_url}/labels").
            to_return(status: 201,
                      body: fixture("gitlab", "label.json"),
                      headers: json_header)
        end

        it "creates a 'dependencies' label" do
          labeler.create_default_labels_if_required

          expect(WebMock).
            to have_requested(:post, "#{repo_api_url}/labels").
            with(
              body: "description=Pull%20requests%20that%20update%20a"\
                    "%20dependency%20file&name=dependencies&color=%230025ff"
            )
          expect(labeler.labels_for_pr).to include("dependencies")
        end
      end

      context "when there is a custom dependencies label" do
        before do
          stub_request(:get, "#{repo_api_url}/labels").
            to_return(status: 200,
                      body: fixture("gitlab", "labels_with_custom.json"),
                      headers: json_header)
        end

        it "does not create a 'dependencies' label" do
          labeler.create_default_labels_if_required

          expect(WebMock).
            to_not have_requested(:post, "#{repo_api_url}/labels")
        end
      end

      context "when a custom dependencies label has been requested" do
        let(:custom_labels) { ["wontfix"] }

        it "does not create a 'dependencies' label" do
          labeler.create_default_labels_if_required

          expect(WebMock).
            to_not have_requested(:post, "#{repo_api_url}/labels")
        end

        context "that doesn't exist" do
          let(:custom_labels) { ["non-existent"] }

          it "does not create any labels" do
            labeler.create_default_labels_if_required

            expect(WebMock).
              to_not have_requested(:post, "#{repo_api_url}/labels")
          end
        end
      end

      context "for an update that fixes a security vulnerability" do
        let(:includes_security_fixes) { true }

        context "when the 'security' label doesn't yet exist" do
          before do
            stub_request(:post, "#{repo_api_url}/labels").
              to_return(status: 201,
                        body: fixture("gitlab", "label.json"),
                        headers: json_header)
          end

          it "creates a 'security' label" do
            labeler.create_default_labels_if_required

            expect(WebMock).
              to have_requested(:post, "#{repo_api_url}/labels").
              with(
                body: "description=Pull%20requests%20that%20address%20a"\
                    "%20security%20vulnerability&name=security&color=%23ee0701"
              )
            expect(labeler.labels_for_pr).to include("security")
          end
        end

        context "when a 'security' label already exist" do
          before do
            stub_request(:get, "#{repo_api_url}/labels").
              to_return(status: 200,
                        body: fixture("gitlab", "labels_with_security.json"),
                        headers: json_header)
          end

          it "does not creates a 'security' label" do
            labeler.create_default_labels_if_required

            expect(WebMock).
              to_not have_requested(:post, "#{repo_api_url}/labels")
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
      let(:repo_api_url) { "https://api.github.com/repos/#{source.repo}" }
      before do
        stub_request(:get, "#{repo_api_url}/labels?per_page=100").
          to_return(status: 200,
                    body: fixture("github", "labels_with_dependencies.json"),
                    headers: json_header)
      end

      context "when a 'dependencies' label exists" do
        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100").
            to_return(status: 200,
                      body: fixture("github", "labels_with_dependencies.json"),
                      headers: json_header)
        end

        it { is_expected.to eq(["dependencies"]) }

        context "for a security fix" do
          let(:includes_security_fixes) { true }
          before do
            stub_request(:get, "#{repo_api_url}/labels?per_page=100").
              to_return(status: 200,
                        body: fixture("github", "labels_with_security.json"),
                        headers: json_header)
          end

          it { is_expected.to eq(%w(dependencies security)) }
        end
      end

      context "when a 'ruby' label exists" do
        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100").
            to_return(
              status: 200,
              body: fixture("github", "labels_with_language.json"),
              headers: json_header
            )
        end

        it { is_expected.to eq(["dependencies"]) }

        context "and label_language is true" do
          let(:label_language) { true }
          it { is_expected.to match_array(%w(dependencies ruby)) }
        end
      end

      context "when a custom dependencies label exists" do
        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100").
            to_return(status: 200,
                      body: fixture("github", "labels_with_custom.json"),
                      headers: json_header)
        end

        it { is_expected.to eq(["Dependency: Gems"]) }
      end

      context "when asking for custom labels" do
        let(:custom_labels) { ["wontfix"] }
        it { is_expected.to eq(["wontfix"]) }

        context "that don't exist" do
          let(:custom_labels) { ["non-existent"] }
          it { is_expected.to eq([]) }
        end

        context "when only one doesn't exist" do
          let(:custom_labels) { %w(wontfix non-existent) }
          it { is_expected.to eq(["wontfix"]) }
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
        stub_request(:get, "#{repo_api_url}/labels").
          to_return(status: 200,
                    body: fixture("gitlab", "labels_with_dependencies.json"),
                    headers: json_header)
      end

      context "when a 'dependencies' label exists" do
        before do
          stub_request(:get, "#{repo_api_url}/labels").
            to_return(status: 200,
                      body: fixture("gitlab", "labels_with_dependencies.json"),
                      headers: json_header)
        end

        it { is_expected.to eq(["dependencies"]) }

        context "for a security fix" do
          let(:includes_security_fixes) { true }
          before do
            stub_request(:get, "#{repo_api_url}/labels").
              to_return(status: 200,
                        body: fixture("github", "labels_with_security.json"),
                        headers: json_header)
          end

          it { is_expected.to eq(%w(dependencies security)) }
        end
      end

      context "when a custom dependencies label exists" do
        before do
          stub_request(:get, "#{repo_api_url}/labels").
            to_return(status: 200,
                      body: fixture("gitlab", "labels_with_custom.json"),
                      headers: json_header)
        end

        it { is_expected.to eq(["Dependency: Gems"]) }
      end

      context "when asking for custom labels" do
        let(:custom_labels) { ["critical"] }
        it { is_expected.to eq(["critical"]) }

        context "that don't exist" do
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
        stub_request(:post, "#{repo_api_url}/issues/1/labels").
          to_return(status: 200,
                    body: fixture("github", "create_label.json"),
                    headers: json_header)
      end

      context "when a 'dependencies' label already exists" do
        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100").
            to_return(status: 200,
                      body: fixture("github", "labels_with_dependencies.json"),
                      headers: json_header)
        end

        it "labels the PR" do
          label_pr

          expect(WebMock).
            to have_requested(:post, "#{repo_api_url}/issues/1/labels").
            with(body: '["dependencies"]')
        end

        context "for a security fix" do
          let(:includes_security_fixes) { true }
          before do
            stub_request(:get, "#{repo_api_url}/labels?per_page=100").
              to_return(status: 200,
                        body: fixture("github", "labels_with_security.json"),
                        headers: json_header)
          end

          it "labels the PR" do
            label_pr

            expect(WebMock).
              to have_requested(:post, "#{repo_api_url}/issues/1/labels").
              with(body: '["dependencies","security"]')
          end
        end
      end

      context "when requesting custom labels that don't exist" do
        let(:custom_labels) { ["non-existent"] }
        before do
          stub_request(:get, "#{repo_api_url}/labels?per_page=100").
            to_return(status: 200,
                      body: fixture("github", "labels_with_dependencies.json"),
                      headers: json_header)
        end

        it "does not label the PR" do
          label_pr

          expect(WebMock).
            to_not have_requested(:post, "#{repo_api_url}/issues/1/labels")
        end
      end
    end
  end
end
