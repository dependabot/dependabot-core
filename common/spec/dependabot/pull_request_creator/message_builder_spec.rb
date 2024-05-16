# typed: false
# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator/message_builder"

RSpec.describe Dependabot::PullRequestCreator::MessageBuilder do
  let(:builder) do
    described_class.new(
      source: source,
      dependencies: dependencies,
      files: files,
      credentials: credentials,
      pr_message_header: pr_message_header,
      pr_message_footer: pr_message_footer,
      commit_message_options: commit_message_options,
      vulnerabilities_fixed: vulnerabilities_fixed,
      github_redirection_service: github_redirection_service,
      dependency_group: dependency_group,
      ignore_conditions: ignore_conditions
    )
  end

  let(:source) do
    Dependabot::Source.new(provider: "github", repo: "gocardless/bump")
  end
  let(:dependencies) { [dependency] }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      previous_version: "1.4.0",
      package_manager: "dummy",
      requirements:
        [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }],
      previous_requirements:
        [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }],
      metadata: metadata
    )
  end
  let(:files) { [gemfile, gemfile_lock] }
  let(:credentials) { github_credentials }
  let(:pr_message_header) { nil }
  let(:pr_message_footer) { nil }
  let(:commit_message_options) { { signoff_details: signoff_details, trailers: trailers } }
  let(:signoff_details) { nil }
  let(:trailers) { nil }
  let(:vulnerabilities_fixed) { { "business" => [] } }
  let(:github_redirection_service) { "redirect.github.com" }
  let(:dependency_group) { nil }
  let(:ignore_conditions) { [] }
  let(:metadata) { {} }

  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: fixture("ruby", "gemfiles", "Gemfile")
    )
  end
  let(:gemfile_lock) do
    Dependabot::DependencyFile.new(
      name: "Gemfile.lock",
      content: fixture("ruby", "gemfiles", "Gemfile")
    )
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:watched_repo_url) { "https://api.github.com/repos/#{source.repo}" }
  def commits_details(base:, head:)
    "<details>\n" \
      "<summary>Commits</summary>\n" \
      "<ul>\n" \
      "<li><a href=\"https://github.com/gocardless/business/commit/" \
      "26f4887ec647493f044836363537e329d9d213aa\"><code>26f4887</code></a> " \
      "Bump version to v1.4.0</li>\n" \
      "<li><a href=\"https://github.com/gocardless/business/commit/" \
      "7abe4c2dc0161904c40c221a48999d12995fbea7\"><code>7abe4c2</code></a> " \
      "[Fix <a href=\"https://redirect.github.com/gocardless/" \
      "business/issues/9\">#9</a>] Allow custom calendars</li>\n" \
      "<li><a href=\"https://github.com/gocardless/business/commit/" \
      "1c72c35ff2aa9d7ce0403d7fd4aa010d94723076\"><code>1c72c35</code></a> " \
      "Allow custom calendars</li>\n" \
      "<li><a href=\"https://github.com/gocardless/business/commit/" \
      "5555535ff2aa9d7ce0403d7fd4aa010d94723076\"><code>5555535</code>" \
      "</a></li>\n" \
      "<li><a href=\"https://github.com/gocardless/business/commit/" \
      "0bfb8c3f0d2701abf9248185beeb8adf643374f6\"><code>0bfb8c3</code></a> " \
      "Spacing: <a href=\"https://redirect.github.com/my/repo/" \
      "pull/5\">my/repo#5</a></li>\n" \
      "<li><a href=\"https://github.com/gocardless/business/commit/" \
      "a5970daf0b824e4c3974e57474b6cf9e39a11d0f\"><code>a5970da</code></a> " \
      "Merge pull request <a href=\"https://redirect.github.com/" \
      "gocardless/business/issues/8\">#8</a> " \
      "from gocardless/rename-sepa-to-ecb</li>\n" \
      "<li><a href=\"https://github.com/gocardless/business/commit/" \
      "d2eb29beda934c14220146c82f830de2edd63a25\"><code>d2eb29b</code></a> " \
      "<a href=\"https://redirect.github.com/gocardless/business/" \
      "issues/12\">12</a> Remove <em>SEPA</em> " \
      "calendar (replaced by TARGET)</li>\n" \
      "<li>See full diff in <a href=\"https://github.com/gocardless/business/" \
      "compare/#{base}...#{head}\">compare view</a></li>\n" \
      "</ul>\n" \
      "</details>\n"
  end

  shared_context "with multiple git sources" do
    let(:dependency) do
      Dependabot::Dependency.new(
        name: "actions/checkout",
        version: "aabbfeb2ce60b5bd82389903509092c4648a9713",
        previous_version: nil,
        package_manager: "dummy",
        requirements: [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@v2.1.0" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v2.2.0",
            branch: nil
          }
        }, {
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@master" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v2.2.0",
            branch: nil
          }
        }],
        previous_requirements: [{
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@v2.1.0" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "v2.1.0",
            branch: nil
          }
        }, {
          requirement: nil,
          groups: [],
          file: ".github/workflows/workflow.yml",
          metadata: { declaration_string: "actions/checkout@master" },
          source: {
            type: "git",
            url: "https://github.com/actions/checkout",
            ref: "master",
            branch: nil
          }
        }]
      )
    end
  end

  describe "#pr_name" do
    subject(:pr_name) { builder.pr_name }

    describe "for an application" do
      context "when that doesn't use a commit convention" do
        before do
          stub_request(:get, watched_repo_url + "/commits?per_page=100")
            .to_return(
              status: 200,
              body: commits_response,
              headers: json_header
            )
        end
        let(:commits_response) { fixture("github", "commits.json") }

        it { is_expected.to eq("Bump business from 1.4.0 to 1.5.0") }

        context "when but the internet goes down" do
          before do
            stub_request(:any, /.*/).to_raise(SocketError)
          end

          it { is_expected.to eq("bump business from 1.4.0 to 1.5.0") }
        end

        context "when but does have prefixed commits" do
          let(:commits_response) { fixture("github", "commits_prefixed.json") }

          it {
            is_expected.to eq("build(deps): bump business from 1.4.0 to 1.5.0")
          }
        end

        context "when that 409s when asked for commits" do
          before do
            stub_request(:get, watched_repo_url + "/commits?per_page=100")
              .to_return(status: 409, headers: json_header)
          end

          it { is_expected.to eq("Bump business from 1.4.0 to 1.5.0") }
        end

        context "when from GitLab" do
          let(:source) do
            Dependabot::Source.new(provider: "gitlab", repo: "gocardless/bump")
          end
          let(:watched_repo_url) do
            "https://gitlab.com/api/v4/projects/" \
              "#{CGI.escape(source.repo)}/repository"
          end
          let(:commits_response) { fixture("gitlab", "commits.json") }
          before do
            stub_request(:get, watched_repo_url + "/commits")
              .to_return(
                status: 200,
                body: commits_response,
                headers: json_header
              )
          end

          it { is_expected.to eq("Bump business from 1.4.0 to 1.5.0") }
        end

        context "with a security vulnerability fixed" do
          let(:vulnerabilities_fixed) { { business: [{}] } }
          it { is_expected.to start_with("[Security] Bump business") }
        end

        context "with two dependencies" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business2",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependencies) { [dependency, dependency2] }

          it { is_expected.to eq("Bump business and business2") }

          context "when for a Maven property update" do
            let(:dependency) do
              Dependabot::Dependency.new(
                name: "org.springframework:spring-beans",
                version: "4.3.15.RELEASE",
                previous_version: "4.3.12.RELEASE",
                package_manager: "maven",
                requirements: [{
                  file: "pom.xml",
                  requirement: "4.3.15.RELEASE",
                  groups: [],
                  source: nil,
                  metadata: { property_name: "springframework.version" }
                }],
                previous_requirements: [{
                  file: "pom.xml",
                  requirement: "4.3.12.RELEASE",
                  groups: [],
                  source: nil,
                  metadata: { property_name: "springframework.version" }
                }]
              )
            end

            it "has the right name" do
              expect(pr_name)
                .to eq(
                  "Bump springframework.version " \
                  "from 4.3.12.RELEASE to 4.3.15.RELEASE"
                )
            end
          end

          context "when for a dependency set update" do
            let(:dependency) do
              Dependabot::Dependency.new(
                name: "org.springframework:spring-beans",
                version: "4.3.15.RELEASE",
                previous_version: "4.3.12.RELEASE",
                package_manager: "maven",
                requirements: [{
                  file: "pom.xml",
                  requirement: "4.3.15.RELEASE",
                  groups: [],
                  source: nil,
                  metadata: {
                    dependency_set: {
                      group: "springframework",
                      version: "4.3.12.RELEASE"
                    }
                  }
                }],
                previous_requirements: [{
                  file: "pom.xml",
                  requirement: "4.3.12.RELEASE",
                  groups: [],
                  source: nil,
                  metadata: {
                    dependency_set: {
                      group: "springframework",
                      version: "4.3.12.RELEASE"
                    }
                  }
                }]
              )
            end

            it "has the right name" do
              expect(pr_name)
                .to eq(
                  "Bump springframework dependency set " \
                  "from 4.3.12.RELEASE to 4.3.15.RELEASE"
                )
            end
          end
        end

        context "with two dependencies with the same name" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business",
              version: "2.3.0",
              previous_version: "2.1.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependencies) { [dependency, dependency2] }
          it { is_expected.to eq("Bump business") }
        end

        context "with three dependencies" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business2",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency3) do
            Dependabot::Dependency.new(
              name: "business3",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependencies) { [dependency, dependency2, dependency3] }

          it { is_expected.to eq("Bump business, business2 and business3") }
        end

        context "with a directory specified" do
          let(:gemfile) do
            Dependabot::DependencyFile.new(
              name: "Gemfile",
              content: fixture("ruby", "gemfiles", "Gemfile"),
              directory: "directory"
            )
          end

          it "includes the directory" do
            expect(pr_name)
              .to eq("Bump business from 1.4.0 to 1.5.0 in /directory")
          end
        end

        context "with SHA-1 versions" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "business",
              version: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2",
              previous_version: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
              package_manager: "dummy",
              requirements: [{
                file: "Gemfile",
                requirement: ">= 0",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/gocardless/business",
                  ref: new_ref
                }
              }],
              previous_requirements: [{
                file: "Gemfile",
                requirement: ">= 0",
                groups: [],
                source: {
                  type: "git",
                  url: "https://github.com/gocardless/business",
                  ref: old_ref
                }
              }]
            )
          end
          let(:new_ref) { nil }
          let(:old_ref) { nil }

          it "truncates the version" do
            expect(pr_name).to eq("Bump business from `2468a02` to `cff701b`")
          end

          context "when due to a ref change" do
            let(:new_ref) { "v1.1.0" }
            let(:old_ref) { "v1.0.0" }

            it "uses the refs" do
              expect(pr_name).to eq("Bump business from v1.0.0 to v1.1.0")
            end
          end
        end

        context "with a Docker digest update" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "ubuntu",
              version: "17.10",
              previous_version: previous_version,
              package_manager: "docker",
              requirements: [{
                file: "Dockerfile",
                requirement: nil,
                groups: [],
                source: {
                  type: "digest",
                  digest: "18305429afa14ea462f810146ba44d4363ae76e4c8d" \
                          "fc38288cf73aa07485005"
                }
              }],
              previous_requirements: [{
                file: "Dockerfile",
                requirement: nil,
                groups: [],
                source: {
                  type: "digest",
                  digest: "2167a21baaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" \
                          "aaaaaaaaaaaaaaaaaaaaa"
                }
              }]
            )
          end
          let(:previous_version) { "17.10" }

          it "truncates the version" do
            expect(pr_name).to eq("Bump ubuntu from `2167a21` to `1830542`")
          end

          context "when due to a tag change" do
            let(:previous_version) { "17.04" }

            it "uses the tags" do
              expect(pr_name).to eq("Bump ubuntu from 17.04 to 17.10")
            end
          end
        end

        context "with a vendored .gemspec" do
          let(:files) { [gemfile, gemfile_lock, gemspec] }
          let(:gemspec) do
            Dependabot::DependencyFile.new(
              name: "vendor/cache/dep/git.gemspec",
              content: fixture("ruby", "gemspecs", "example")
            )
          end

          it { is_expected.to eq("Bump business from 1.4.0 to 1.5.0") }
        end
      end

      context "when that uses angular commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits?per_page=100")
            .to_return(status: 200,
                       body: fixture("github", "commits_angular.json"),
                       headers: json_header)
        end

        it do
          is_expected.to eq("chore(deps): bump business from 1.4.0 to 1.5.0")
        end

        context "with capitalizes them" do
          before do
            stub_request(:get, watched_repo_url + "/commits?per_page=100")
              .to_return(
                status: 200,
                body: fixture("github", "commits_angular_capitalized.json"),
                headers: json_header
              )
          end

          it do
            is_expected.to eq("Chore(deps): Bump business from 1.4.0 to 1.5.0")
          end
        end

        context "with capitalizes the message but not the prefix" do
          before do
            stub_request(:get, watched_repo_url + "/commits?per_page=100")
              .to_return(
                status: 200,
                body: fixture("github", "commits_angular_sentence_case.json"),
                headers: json_header
              )
          end

          it do
            is_expected.to eq("chore(deps): Bump business from 1.4.0 to 1.5.0")
          end

          context "with with commit messages explicitly configured" do
            let(:commit_message_options) { super().merge(prefix: "chore(dependencies)") }

            it do
              is_expected.to eq("chore(dependencies): Bump business from 1.4.0 to 1.5.0")
            end
          end
        end

        context "with a security vulnerability fixed" do
          let(:vulnerabilities_fixed) { { business: [{}] } }
          it { is_expected.to start_with("chore(deps): [security] bump") }
        end

        context "with a dev dependency" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "business",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [{
                file: "Gemfile",
                requirement: "~> 1.5.0",
                groups: ["test"],
                source: nil
              }],
              previous_requirements: [{
                file: "Gemfile",
                requirement: "~> 1.4.0",
                groups: ["test"],
                source: nil
              }]
            )
          end

          it { is_expected.to start_with("chore(deps-dev): bump") }
        end
      end

      context "when that uses eslint commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits?per_page=100")
            .to_return(status: 200,
                       body: fixture("github", "commits_eslint.json"),
                       headers: json_header)
        end

        it do
          is_expected.to eq("Upgrade: Bump business from 1.4.0 to 1.5.0")
        end

        context "with a security vulnerability fixed" do
          let(:vulnerabilities_fixed) { { business: [{}] } }
          it { is_expected.to start_with("Upgrade: [Security] Bump") }
        end
      end

      describe "that uses gitmoji commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits?per_page=100")
            .to_return(status: 200,
                       body: fixture("github", "commits_gitmoji.json"),
                       headers: json_header)
        end

        it { is_expected.to start_with("⬆️ Bump business") }

        context "with a security vulnerability fixed" do
          let(:vulnerabilities_fixed) { { business: [{}] } }
          it { is_expected.to start_with("⬆️🔒 Bump business") }
        end
      end

      context "with multiple git source requirements", :vcr do
        include_context "with multiple git sources"

        it "has the correct name" do
          is_expected.to eq(
            "Update actions/checkout requirement to v2.2.0"
          )
        end
      end
    end

    context "when for a library" do
      let(:files) { [gemfile, gemfile_lock, gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          name: "bump.gemspec",
          content: fixture("ruby", "gemspecs", "example")
        )
      end

      context "when that doesn't use a commit convention" do
        before do
          stub_request(:get, watched_repo_url + "/commits?per_page=100")
            .to_return(status: 200, body: "[]", headers: json_header)
        end

        it "has the right title" do
          expect(pr_name)
            .to eq("Update business requirement from ~> 1.4.0 to ~> 1.5.0")
        end

        context "with a git dependency" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "business",
              version: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
              previous_version: nil,
              package_manager: "dummy",
              requirements: [{
                file: "package.json",
                requirement: nil,
                groups: [],
                source: {
                  ref: "v0.4.1",
                  url: "https://github.com/wireapp/wire-web-config-default",
                  type: "git",
                  branch: nil
                }
              }],
              previous_requirements: [{
                file: "Gemfile",
                requirement: nil,
                groups: [],
                source: {
                  ref: "v0.3.0",
                  url: "https://github.com/wireapp/wire-web-config-default",
                  type: "git",
                  branch: nil
                }
              }]
            )
          end

          it "has the right title" do
            expect(pr_name)
              .to eq("Update business requirement from v0.3.0 to v0.4.1")
          end

          context "when switching from a SHA-1 version to a release" do
            let(:dependency) do
              Dependabot::Dependency.new(
                name: "business",
                version: "1.5.0",
                previous_version: nil,
                package_manager: "dummy",
                requirements: [{
                  file: "Gemfile",
                  requirement: "~> 1.5.0",
                  groups: [],
                  source: nil
                }],
                previous_requirements: [{
                  file: "Gemfile",
                  requirement: nil,
                  groups: [],
                  source: {
                    type: "git",
                    url: "https://github.com/gocardless/business",
                    ref: "2468a0",
                    branch: nil
                  }
                }]
              )
            end

            it "has the right title" do
              expect(pr_name)
                .to eq("Update business requirement from 2468a0 to ~> 1.5.0")
            end
          end
        end

        context "with a security vulnerability fixed" do
          let(:vulnerabilities_fixed) { { business: [{}] } }
          it { is_expected.to start_with("[Security] Update business") }
        end

        context "with two dependencies" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business2",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependencies) { [dependency, dependency2] }

          it "includes both dependencies" do
            expect(pr_name)
              .to eq("Update requirements for business and business2")
          end
        end

        context "with two dependencies with the same name" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business",
              version: "2.3.0",
              previous_version: "2.1.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependencies) { [dependency, dependency2] }
          it { is_expected.to eq("Update requirements for business") }
        end

        context "with three dependencies" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business2",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency3) do
            Dependabot::Dependency.new(
              name: "business3",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependencies) { [dependency, dependency2, dependency3] }

          it "includes all three dependencies" do
            expect(pr_name)
              .to eq("Update requirements for business, business2 and business3")
          end
        end

        context "with a directory specified" do
          let(:gemfile) do
            Dependabot::DependencyFile.new(
              name: "Gemfile",
              content: fixture("ruby", "gemfiles", "Gemfile"),
              directory: "directory"
            )
          end

          it "includes the directory" do
            expect(pr_name)
              .to eq("Update business requirement from ~> 1.4.0 to ~> 1.5.0 " \
                     "in /directory")
          end
        end
      end

      context "when that uses angular commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits?per_page=100")
            .to_return(status: 200,
                       body: fixture("github", "commits_angular.json"),
                       headers: json_header)
        end

        it "uses an angular commit prefix" do
          expect(pr_name)
            .to eq("chore(deps): update business requirement from ~> 1.4.0 " \
                   "to ~> 1.5.0")
        end

        context "with a security vulnerability fixed" do
          let(:vulnerabilities_fixed) { { business: [{}] } }
          it { is_expected.to start_with("chore(deps): [security] update") }
        end
      end

      context "when that uses eslint commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits?per_page=100")
            .to_return(status: 200,
                       body: fixture("github", "commits_eslint.json"),
                       headers: json_header)
        end

        it "uses an eslint commit prefix" do
          expect(pr_name)
            .to eq("Upgrade: Update business requirement from ~> 1.4.0 " \
                   "to ~> 1.5.0")
        end

        context "with a security vulnerability fixed" do
          let(:vulnerabilities_fixed) { { business: [{}] } }
          it { is_expected.to start_with("Upgrade: [Security] Update") }
        end
      end
    end

    context "when for a dependency group with one dependency" do
      let(:dependency_group) do
        Dependabot::DependencyGroup.new(name: "all-the-things", rules: { patterns: ["*"] })
      end

      before do
        stub_request(:get, watched_repo_url + "/commits?per_page=100")
          .to_return(
            status: 200,
            body: commits_response,
            headers: json_header
          )
      end
      let(:commits_response) { fixture("github", "commits.json") }

      it { is_expected.to eq("Bump business from 1.4.0 to 1.5.0 in the all-the-things group") }

      context "with two dependencies" do
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "business2",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: []
          )
        end
        let(:dependencies) { [dependency, dependency2] }

        it { is_expected.to eq("Bump the all-the-things group with 2 updates") }
      end

      context "with two dependencies with the same name" do
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: []
          )
        end
        let(:dependencies) { [dependency, dependency2] }

        it { is_expected.to eq("Bump the all-the-things group with 1 update") }
      end

      context "with three dependencies" do
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "business2",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: []
          )
        end
        let(:dependency3) do
          Dependabot::Dependency.new(
            name: "business3",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: []
          )
        end
        let(:dependencies) { [dependency, dependency2, dependency3] }

        it { is_expected.to eq("Bump the all-the-things group with 3 updates") }
      end

      context "with a directory specified" do
        let(:gemfile) do
          Dependabot::DependencyFile.new(
            name: "Gemfile",
            content: fixture("ruby", "gemfiles", "Gemfile"),
            directory: "directory"
          )
        end
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "business2",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: []
          )
        end
        let(:dependencies) { [dependency, dependency2] }

        it "includes the directory" do
          expect(pr_name)
            .to eq("Bump the all-the-things group in /directory with 2 updates")
        end
      end
    end
    context "when for a multi-directory group with one dependency" do
      let(:source) do
        Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directories: ["/foo", "/bar"])
      end
      let(:dependency_group) do
        Dependabot::DependencyGroup.new(name: "go_modules", rules: { patterns: ["*"] })
      end
      let(:metadata) { { directory: "/foo" } }

      before do
        stub_request(:get, watched_repo_url + "/commits?per_page=100")
          .to_return(
            status: 200,
            body: commits_response,
            headers: json_header
          )
      end
      let(:commits_response) { fixture("github", "commits.json") }

      it { is_expected.to eq("Bump business from 1.4.0 to 1.5.0 in the go_modules group across 1 directory") }

      context "with two dependencies" do
        let(:metadata) { { directory: "/foo" } }
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "business2",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: [],
            metadata: { directory: "/bar" }
          )
        end
        let(:dependencies) { [dependency, dependency2] }

        it { is_expected.to eq("Bump the go_modules group across 2 directories with 2 updates") }
      end
    end
  end

  describe "#pr_message" do
    subject(:pr_message) { builder.pr_message }

    let(:business_repo_url) do
      "https://api.github.com/repos/gocardless/business"
    end

    before do
      stub_request(:get, watched_repo_url + "/commits?per_page=100")
        .to_return(status: 200, body: "[]", headers: json_header)

      stub_request(:get, business_repo_url)
        .to_return(status: 200,
                   body: fixture("github", "business_repo.json"),
                   headers: json_header)
      stub_request(:get, "#{business_repo_url}/contents/")
        .to_return(status: 200,
                   body: fixture("github", "business_files.json"),
                   headers: json_header)
      stub_request(:get, "#{business_repo_url}/releases?per_page=100")
        .to_return(status: 200,
                   body: fixture("github", "business_releases.json"),
                   headers: json_header)
      stub_request(:get, "https://api.github.com/repos/gocardless/" \
                         "business/contents/CHANGELOG.md?ref=master")
        .to_return(status: 200,
                   body: fixture("github", "changelog_contents.json"),
                   headers: json_header)
      stub_request(:get, "#{business_repo_url}/commits?sha=v1.5.0")
        .to_return(status: 200,
                   body: fixture("github", "commits-business-1.4.0.json"),
                   headers: json_header)
      stub_request(:get, "#{business_repo_url}/commits?sha=v1.4.0")
        .to_return(status: 200,
                   body: fixture("github", "commits-business-1.3.0.json"),
                   headers: json_header)
      stub_request(:get, "https://rubygems.org/api/v1/gems/business.json")
        .to_return(status: 200, body: fixture("ruby", "rubygems_response.json"))

      service_pack_url =
        "https://github.com/gocardless/business.git/info/refs" \
        "?service=git-upload-pack"
      stub_request(:get, service_pack_url)
        .to_return(
          status: 200,
          body: fixture("git", "upload_packs", "business"),
          headers: {
            "content-type" => "application/x-git-upload-pack-advertisement"
          }
        )
    end

    describe "for an application" do
      it "has the right text" do
        expect(pr_message)
          .to eq(
            "Bumps [business](https://github.com/gocardless/business) " \
            "from 1.4.0 to 1.5.0.\n" \
            "<details>\n" \
            "<summary>Changelog</summary>\n" \
            "<p><em>Sourced from <a href=\"https://github.com/gocardless/" \
            "business/blob/master/CHANGELOG.md\">" \
            "business's changelog</a>.</em></p>\n" \
            "<blockquote>\n" \
            "<h2>1.5.0 - June 2, 2015</h2>\n" \
            "<ul>\n" \
            "<li>Add 2016 holiday definitions</li>\n" \
            "</ul>\n" \
            "</blockquote>\n" \
            "</details>\n" \
            "#{commits_details(base: 'v1.4.0', head: 'v1.5.0')}" \
            "<br />\n"
          )
      end

      context "when there's a network error" do
        before do
          stub_request(:any, /.*/).to_raise(SocketError)
        end

        it "has a blank message" do
          expect(pr_message)
            .to eq("")
        end
      end

      context "without a github link proxy" do
        let(:github_redirection_service) { nil }

        it "has the right text" do
          commits = commits_details(base: "v1.4.0", head: "v1.5.0")
                    .gsub("redirect.github.com", "github.com")
          expect(pr_message)
            .to eq(
              "Bumps [business](https://github.com/gocardless/business) " \
              "from 1.4.0 to 1.5.0.\n" \
              "<details>\n" \
              "<summary>Changelog</summary>\n" \
              "<p><em>Sourced from <a href=\"https://github.com/gocardless/" \
              "business/blob/master/CHANGELOG.md\">" \
              "business's changelog</a>.</em></p>\n" \
              "<blockquote>\n" \
              "<h2>1.5.0 - June 2, 2015</h2>\n" \
              "<ul>\n" \
              "<li>Add 2016 holiday definitions</li>\n" \
              "</ul>\n" \
              "</blockquote>\n" \
              "</details>\n" \
              "#{commits}" \
              "<br />\n"
            )
        end
      end

      context "with a relative link in the changelog" do
        before do
          stub_request(:get, "https://api.github.com/repos/gocardless/" \
                             "business/contents/CHANGELOG.md?ref=master")
            .to_return(
              status: 200,
              body: fixture("github", "changelog_contents_rel_link.json"),
              headers: json_header
            )
        end

        it "has the right text" do
          expect(pr_message)
            .to eq(
              "Bumps [business](https://github.com/gocardless/business) " \
              "from 1.4.0 to 1.5.0.\n" \
              "<details>\n" \
              "<summary>Changelog</summary>\n" \
              "<p><em>Sourced from <a href=\"https://github.com/gocardless/" \
              "business/blob/master/CHANGELOG.md\">" \
              "business's changelog</a>.</em></p>\n" \
              "<blockquote>\n" \
              "<h2>1.5.0 - June 2, 2015</h2>\n" \
              "<ul>\n" \
              "<li>Add 2016 holiday definitions</li>\n" \
              "<li>See <a href=\"https://github.com/gocardless/business/blob/" \
              "master/holiday/README.md\">holiday-deps</a></li>\n" \
              "</ul>\n" \
              "</blockquote>\n" \
              "</details>\n" \
              "#{commits_details(base: 'v1.4.0', head: 'v1.5.0')}" \
              "<br />\n"
            )
        end
      end

      context "with SHA-1 versions" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2",
            previous_version: previous_version,
            package_manager: "dummy",
            requirements: [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/gocardless/business",
                ref: new_ref
              }
            }],
            previous_requirements: [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/gocardless/business",
                ref: old_ref
              }
            }]
          )
        end
        let(:previous_version) { "2468a02a6230e59ed1232d95d1ad3ef157195b03" }
        let(:new_ref) { nil }
        let(:old_ref) { nil }

        before do
          stub_request(
            :get,
            "#{business_repo_url}/commits?sha=" \
            "2468a02a6230e59ed1232d95d1ad3ef157195b03"
          ).to_return(
            status: 200,
            body: fixture("github", "commits-business-1.3.0.json"),
            headers: json_header
          )
          stub_request(
            :get,
            "#{business_repo_url}/commits?sha=" \
            "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2"
          ).to_return(
            status: 200,
            body: fixture("github", "commits-business-1.4.0.json"),
            headers: json_header
          )
        end

        it "has the right text" do
          commits_details = commits_details(
            base: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
            head: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2"
          )
          expect(pr_message).to eq(
            "Bumps [business](https://github.com/gocardless/business) " \
            "from `2468a02` to `cff701b`.\n" \
            "#{commits_details}" \
            "<br />\n"
          )
        end

        context "when due to a ref change" do
          let(:new_ref) { "v1.1.0" }
          let(:old_ref) { "v1.0.0" }

          it "has the right text" do
            commits_details = commits_details(
              base: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
              head: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2"
            )
            expect(pr_message)
              .to eq(
                "Bumps [business](https://github.com/gocardless/business) " \
                "from v1.0.0 to v1.1.0.\n" \
                "<details>\n" \
                "<summary>Changelog</summary>\n" \
                "<p><em>Sourced from <a href=\"https://github.com/gocardless/" \
                "business/blob/master/CHANGELOG.md\">" \
                "business's changelog</a>.</em></p>\n" \
                "<blockquote>\n" \
                "<h2>1.1.0 - September 30, 2014</h2>\n" \
                "<ul>\n" \
                "<li>Add 2015 holiday definitions</li>\n" \
                "</ul>\n" \
                "</blockquote>\n" \
                "</details>\n" \
                "#{commits_details}" \
                "<br />\n"
              )
          end

          context "with no previous version" do
            let(:previous_version) { nil }

            before do
              stub_request(:get, "#{business_repo_url}/commits?sha=v1.0.0")
                .to_return(
                  status: 200,
                  body: fixture("github", "commits-business-1.3.0.json"),
                  headers: json_header
                )
            end

            it "has the right text" do
              commits_details = commits_details(
                base: "v1.0.0",
                head: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2"
              )
              expect(pr_message)
                .to eq(
                  "Bumps [business](https://github.com/gocardless/business) " \
                  "from v1.0.0 to v1.1.0.\n" \
                  "<details>\n" \
                  "<summary>Changelog</summary>\n" \
                  "<p><em>Sourced from <a href=\"https://github.com/" \
                  "gocardless/business/blob/master/CHANGELOG.md\">" \
                  "business's changelog</a>.</em></p>\n" \
                  "<blockquote>\n" \
                  "<h2>1.1.0 - September 30, 2014</h2>\n" \
                  "<ul>\n" \
                  "<li>Add 2015 holiday definitions</li>\n" \
                  "</ul>\n" \
                  "</blockquote>\n" \
                  "</details>\n" \
                  "#{commits_details}" \
                  "<br />\n"
                )
            end
          end
        end

        context "when from GitLab" do
          let(:source) do
            Dependabot::Source.new(provider: "gitlab", repo: "gocardless/bump")
          end

          it "sanitizes github links" do
            expect(pr_message).to include(github_redirection_service)
          end
        end

        context "when from Bitbucket" do
          let(:source) do
            Dependabot::Source.new(provider: "bitbucket", repo: "gocardless/bump")
          end

          it "sanitizes github links" do
            expect(pr_message).to eq(
              "Bumps [business](https://github.com/gocardless/business) from `2468a02` to `cff701b`.\n" \
              "# Commits\n\n" \
              "  - [`26f4887`](https://github.com/gocardless/business/commit/" \
              "26f4887ec647493f044836363537e329d9d213aa) Bump version to\n" \
              "    v1.4.0\n" \
              "  - [`7abe4c2`](https://github.com/gocardless/business/commit/" \
              "7abe4c2dc0161904c40c221a48999d12995fbea7) \\[Fix\n" \
              "    [\\#9](https://redirect.github.com/gocardless/business/issues/9)\\] Allow custom calendars\n" \
              "  - [`1c72c35`](https://github.com/gocardless/business/commit/" \
              "1c72c35ff2aa9d7ce0403d7fd4aa010d94723076) Allow custom\n" \
              "    calendars\n" \
              "  - [`5555535`](https://github.com/gocardless/business/commit/" \
              "5555535ff2aa9d7ce0403d7fd4aa010d94723076)\n" \
              "  - [`0bfb8c3`](https://github.com/gocardless/business/commit/" \
              "0bfb8c3f0d2701abf9248185beeb8adf643374f6) Spacing:\n" \
              "    [my/repo\\#5](https://redirect.github.com/my/repo/pull/5)\n" \
              "  - [`a5970da`](https://github.com/gocardless/business/commit/" \
              "a5970daf0b824e4c3974e57474b6cf9e39a11d0f) Merge pull\n" \
              "    request [\\#8](https://redirect.github.com/gocardless/business/issues/8) from" \
              " gocardless/rename-sepa-to-ecb\n" \
              "  - [`d2eb29b`](https://github.com/gocardless/business/commit/" \
              "d2eb29beda934c14220146c82f830de2edd63a25)\n" \
              "    [12](https://redirect.github.com/gocardless/business/issues/12) Remove *SEPA* calendar" \
              " (replaced by TARGET)\n" \
              "  - See full diff in [compare\n" \
              "    view](https://github.com/gocardless/business/compare/2468a02a6230e59ed1232d95d1ad3ef157195b03...cff701b3bfb182afc99a85657d7c9f3d6c1ccce2)\n"
            )
          end
        end

        context "when from codecommit" do
          let(:source) do
            Dependabot::Source.new(
              provider: "codecommit",
              repo: "gocardless/bump"
            )
          end

          it "does not include detail tags" do
            expect(pr_message).not_to include("<details>")
          end

          it "does not include br tags" do
            expect(pr_message).not_to include("<br />")
          end
        end
      end

      context "when switching from a SHA-1 version to a release" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            previous_version: previous_version,
            package_manager: "dummy",
            requirements: [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "Gemfile",
              requirement: ">= 0",
              groups: [],
              source: {
                type: "git",
                url: "https://github.com/gocardless/business"
              }
            }]
          )
        end
        let(:previous_version) { "2468a02a6230e59ed1232d95d1ad3ef157195b03" }

        before do
          stub_request(
            :get,
            "#{business_repo_url}/commits?sha=" \
            "2468a02a6230e59ed1232d95d1ad3ef157195b03"
          ).to_return(
            status: 200,
            body: fixture("github", "commits-business-1.3.0.json"),
            headers: json_header
          )
          stub_request(:get, "#{business_repo_url}/commits?sha=v1.5.0")
            .to_return(
              status: 200,
              body: fixture("github", "commits-business-1.4.0.json"),
              headers: json_header
            )
        end

        it "has the right text" do
          commits_details = commits_details(
            base: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
            head: "v1.5.0"
          )
          expect(pr_message)
            .to eq(
              "Bumps [business](https://github.com/gocardless/business) " \
              "from `2468a02` to 1.5.0. This release includes the previously " \
              "tagged commit.\n" \
              "<details>\n" \
              "<summary>Changelog</summary>\n" \
              "<p><em>Sourced from <a href=\"https://github.com/gocardless/" \
              "business/blob/master/CHANGELOG.md\">" \
              "business's changelog</a>.</em></p>\n" \
              "<blockquote>\n" \
              "<h2>1.5.0 - June 2, 2015</h2>\n" \
              "<ul>\n" \
              "<li>Add 2016 holiday definitions</li>\n" \
              "</ul>\n" \
              "<h2>1.4.0 - December 24, 2014</h2>\n" \
              "<ul>\n" \
              "<li>Add support for custom calendar load paths</li>\n" \
              "<li>Remove the 'sepa' calendar</li>\n" \
              "</ul>\n" \
              "<h2>1.3.0 - December 2, 2014</h2>\n" \
              "<ul>\n" \
              "<li>Add <code>Calendar#previous_business_day</code></li>\n" \
              "</ul>\n" \
              "<h2>1.2.0 - November 15, 2014</h2>\n" \
              "<ul>\n" \
              "<li>Add TARGET calendar</li>\n" \
              "</ul>\n" \
              "<h2>1.1.0 - September 30, 2014</h2>\n" \
              "<ul>\n" \
              "<li>Add 2015 holiday definitions</li>\n" \
              "</ul>\n" \
              "<h2>1.0.0 - June 11, 2014</h2>\n" \
              "<ul>\n" \
              "<li>Initial public release</li>\n" \
              "</ul>\n" \
              "</blockquote>\n" \
              "</details>\n" \
              "#{commits_details}" \
              "<br />\n"
            )
        end

        context "without a previous version" do
          let(:previous_version) { nil }

          it "has the right text" do
            expect(pr_message).to include(
              "Updates the requirements on " \
              "[business](https://github.com/gocardless/business) to permit " \
              "the latest version."
            )
          end
        end
      end

      context "with commits (but no changelog)" do
        before do
          stub_request(:get, "#{business_repo_url}/contents/")
            .to_return(
              status: 200,
              body: fixture("github", "business_files_no_changelog.json"),
              headers: json_header
            )
          stub_request(:get, "#{business_repo_url}/contents/?ref=v1.5.0")
            .to_return(
              status: 200,
              body: fixture("github", "business_files_no_changelog.json"),
              headers: json_header
            )
          stub_request(
            :get,
            "https://api.github.com/repos/gocardless/business/compare/" \
            "v1.4.0...v1.5.0"
          ).with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "business_compare_commits.json"),
              headers: { "Content-Type" => "application/json" }
            )
        end

        it "has the right text" do
          expect(pr_message)
            .to eq(
              "Bumps [business](https://github.com/gocardless/business) from " \
              "1.4.0 to 1.5.0.\n" \
              "#{commits_details(base: 'v1.4.0', head: 'v1.5.0')}" \
              "<br />\n"
            )
        end

        context "with release notes text that can be pulled in" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "business",
              version: "1.6.0",
              previous_version: "1.5.0",
              package_manager: "dummy",
              requirements: [{
                file: "Gemfile",
                requirement: "~> 1.6.0",
                groups: [],
                source: nil
              }],
              previous_requirements: [{
                file: "Gemfile",
                requirement: "~> 1.5.0",
                groups: [],
                source: nil
              }]
            )
          end

          before do
            stub_request(:get, "#{business_repo_url}/contents/?ref=v1.6.0")
              .to_return(
                status: 200,
                body: fixture("github", "business_files_no_changelog.json"),
                headers: json_header
              )
            stub_request(:get, "#{business_repo_url}/commits?sha=v1.6.0")
              .to_return(
                status: 200,
                body: fixture("github", "commits-business-1.4.0.json"),
                headers: json_header
              )
            stub_request(:get, "#{business_repo_url}/commits?sha=v1.5.0")
              .to_return(
                status: 200,
                body: fixture("github", "commits-business-1.3.0.json"),
                headers: json_header
              )
          end

          it "has the right text" do
            expect(pr_message)
              .to eq(
                "Bumps [business](https://github.com/gocardless/business) " \
                "from 1.5.0 to 1.6.0.\n" \
                "<details>\n" \
                "<summary>Release notes</summary>\n" \
                "<p><em>Sourced from <a href=\"https://github.com/gocardless/" \
                "business/releases\">business's releases</a>.</em></p>\n" \
                "<blockquote>\n" \
                "<h2>v1.6.0</h2>\n" \
                "<p>Mad props to <a href=\"https://github.com/greysteil\">" \
                "<code>@\u200Bgreysteil</code></a> and <a href=\"https://github.com/hmarr\">" \
                "<code>@\u200Bhmarr</code></a> for the " \
                "<code>@\u200Bangular/scope</code> work - see <a href=\"https://github.com/" \
                "gocardless/business/blob/HEAD/CHANGELOG.md\">changelog</a>." \
                "</p>\n" \
                "</blockquote>\n" \
                "</details>\n" \
                "#{commits_details(base: 'v1.5.0', head: 'v1.6.0')}" \
                "<br />\n"
              )
          end
        end
      end

      context "with security vulnerabilities fixed" do
        let(:vulnerabilities_fixed) do
          {
            "business" => [{
              "title" => "Serious vulnerability",
              "description" => "A vulnerability that allows arbitrary code\n" \
                               "execution.\n",
              "patched_versions" => ["> 1.5.0"],
              "unaffected_versions" => [],
              "url" => "https://dependabot.com"
            }]
          }
        end

        it "has the right text" do
          expect(pr_message)
            .to start_with(
              "Bumps [business](https://github.com/gocardless/business) " \
              "from 1.4.0 to 1.5.0. **This update includes a security fix.**\n" \
              "<details>\n" \
              "<summary>Vulnerabilities fixed</summary>\n" \
              "<blockquote>\n" \
              "<p><strong>Serious vulnerability</strong>\n" \
              "A vulnerability that allows arbitrary code\n" \
              "execution.</p>\n" \
              "<p>Patched versions: &gt; 1.5.0\n" \
              "Unaffected versions: none</p>\n" \
              "</blockquote>\n" \
              "</details>\n"
            )
        end
      end

      context "with transitive security vulnerabilities fixed" do
        let(:dependencies) { [transitive_dependency, dependency] }
        let(:transitive_dependency) do
          Dependabot::Dependency.new(
            name: "statesman",
            version: "1.6.0",
            previous_version: "1.5.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: []
          )
        end

        before do
          statesman_repo_url =
            "https://api.github.com/repos/gocardless/statesman"
          stub_request(:get, statesman_repo_url)
            .to_return(status: 200,
                       body: fixture("github", "statesman_repo.json"),
                       headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/contents/")
            .to_return(status: 200,
                       body: fixture("github", "statesman_files.json"),
                       headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/releases?per_page=100")
            .to_return(status: 200,
                       body: fixture("github", "business_releases.json"),
                       headers: json_header)
          stub_request(:get, "https://api.github.com/repos/gocardless/" \
                             "statesman/contents/CHANGELOG.md?ref=master")
            .to_return(status: 200,
                       body: fixture("github", "changelog_contents.json"),
                       headers: json_header)
          stub_request(:get, "https://rubygems.org/api/v1/gems/statesman.json")
            .to_return(
              status: 200,
              body: fixture("ruby", "rubygems_response_statesman.json")
            )

          service_pack_url =
            "https://github.com/gocardless/statesman.git/info/refs" \
            "?service=git-upload-pack"
          stub_request(:get, service_pack_url)
            .to_return(
              status: 200,
              body: fixture("git", "upload_packs", "no_tags"),
              headers: {
                "content-type" => "application/x-git-upload-pack-advertisement"
              }
            )
        end

        it "includes details of both dependencies" do
          expect(pr_message)
            .to start_with(
              "Bumps [statesman](https://github.com/gocardless/statesman) to 1.6.0 " \
              "and updates ancestor dependency [business](https://github.com/gocardless/business). " \
              "These dependencies need to be updated together.\n\n" \
              "Updates `statesman` from 1.5.0 to 1.6.0\n" \
              "<details>\n" \
              "<summary>Release notes</summary>\n"
            )
        end
      end

      context "with an upgrade guide that can be pulled in" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            previous_version: "0.9.0",
            package_manager: "dummy",
            requirements: [{
              file: "Gemfile",
              requirement: "~> 1.5.0",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "Gemfile",
              requirement: "~> 0.9.0",
              groups: [],
              source: nil
            }]
          )
        end

        before do
          stub_request(
            :get,
            "https://api.github.com/repos/gocardless/business/compare/" \
            "v0.9.0...v1.5.0"
          ).with(headers: { "Authorization" => "token token" })
            .to_return(
              status: 200,
              body: fixture("github", "business_compare_commits.json"),
              headers: { "Content-Type" => "application/json" }
            )
          stub_request(:get, "#{business_repo_url}/contents/")
            .to_return(
              status: 200,
              body:
                fixture("github", "business_files_with_upgrade_guide.json"),
              headers: json_header
            )
          stub_request(:get, "https://api.github.com/repos/gocardless/" \
                             "business/contents/UPGRADE.md?ref=master")
            .to_return(
              status: 200,
              body: fixture("github", "upgrade_guide_contents.json"),
              headers: json_header
            )
        end

        it "has the right text" do
          expect(pr_message)
            .to start_with(
              "Bumps [business](https://github.com/gocardless/business) from " \
              "0.9.0 to 1.5.0.\n" \
              "<details>\n" \
              "<summary>Changelog</summary>\n" \
              "<p><em>Sourced from <a href=\"https://github.com/gocardless/" \
              "business/blob/master/CHANGELOG.md\">business's changelog</a>." \
              "</em></p>\n" \
              "<blockquote>\n" \
              "<h2>1.5.0 - June 2, 2015</h2>\n" \
              "<ul>\n" \
              "<li>Add 2016 holiday definitions</li>\n" \
              "</ul>\n" \
              "<h2>1.4.0 - December 24, 2014</h2>\n" \
              "<ul>\n" \
              "<li>Add support for custom calendar load paths</li>\n" \
              "<li>Remove the 'sepa' calendar</li>\n" \
              "</ul>\n" \
              "<h2>1.3.0 - December 2, 2014</h2>\n" \
              "<ul>\n" \
              "<li>Add <code>Calendar#previous_business_day</code></li>\n" \
              "</ul>\n" \
              "<h2>1.2.0 - November 15, 2014</h2>\n" \
              "<ul>\n" \
              "<li>Add TARGET calendar</li>\n" \
              "</ul>\n" \
              "<h2>1.1.0 - September 30, 2014</h2>\n" \
              "<ul>\n" \
              "<li>Add 2015 holiday definitions</li>\n" \
              "</ul>\n" \
              "<h2>1.0.0 - June 11, 2014</h2>\n" \
              "<ul>\n" \
              "<li>Initial public release</li>\n" \
              "</ul>\n" \
              "</blockquote>\n" \
              "</details>\n" \
              "<details>\n" \
              "<summary>Upgrade guide</summary>\n" \
              "<p><em>Sourced from <a href=\"https://github.com/gocardless/" \
              "business/blob/master/UPGRADE.md\">business's upgrade guide</a>." \
              "</em></p>\n" \
              "<blockquote>\n" \
              "<h1>UPGRADE GUIDE FROM 2.x to 3.0</h1>"
            )
        end
      end

      context "with a change in maintainer" do
        before do
          allow_any_instance_of(Dependabot::MetadataFinders::Base)
            .to receive(:maintainer_changes)
            .and_return("Maintainer change")
        end

        it "has the right text" do
          expect(pr_message).to include(
            "<details>\n" \
            "<summary>Maintainer changes</summary>\n" \
            "<p>Maintainer change</p>\n" \
            "</details>\n" \
            "<br />"
          )
        end
      end

      context "when updating multiple dependencies" do
        let(:dependencies) { [dependency, dependency2] }
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "statesman",
            version: "1.7.0",
            previous_version: "1.6.0",
            package_manager: "dummy",
            requirements: [{
              file: "Gemfile",
              requirement: "~> 1.7",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "Gemfile",
              requirement: "~> 1.6",
              groups: [],
              source: nil
            }]
          )
        end

        before do
          statesman_repo_url =
            "https://api.github.com/repos/gocardless/statesman"
          stub_request(:get, statesman_repo_url)
            .to_return(status: 200,
                       body: fixture("github", "statesman_repo.json"),
                       headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/contents/")
            .to_return(status: 200,
                       body: fixture("github", "statesman_files.json"),
                       headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/releases?per_page=100")
            .to_return(status: 200,
                       body: fixture("github", "business_releases.json"),
                       headers: json_header)
          stub_request(:get, "https://api.github.com/repos/gocardless/" \
                             "statesman/contents/CHANGELOG.md?ref=master")
            .to_return(status: 200,
                       body: fixture("github", "changelog_contents.json"),
                       headers: json_header)
          stub_request(:get, "https://rubygems.org/api/v1/gems/statesman.json")
            .to_return(
              status: 200,
              body: fixture("ruby", "rubygems_response_statesman.json")
            )

          service_pack_url =
            "https://github.com/gocardless/statesman.git/info/refs" \
            "?service=git-upload-pack"
          stub_request(:get, service_pack_url)
            .to_return(
              status: 200,
              body: fixture("git", "upload_packs", "no_tags"),
              headers: {
                "content-type" => "application/x-git-upload-pack-advertisement"
              }
            )
        end

        it "includes details of both dependencies" do
          expect(pr_message)
            .to eq(
              "Bumps [business](https://github.com/gocardless/business) " \
              "and [statesman](https://github.com/gocardless/statesman). " \
              "These dependencies needed to be updated together.\n" \
              "Updates `business` from 1.4.0 to 1.5.0\n" \
              "<details>\n" \
              "<summary>Changelog</summary>\n" \
              "<p><em>Sourced from <a href=\"https://github.com/gocardless/" \
              "business/blob/master/CHANGELOG.md\">" \
              "business's changelog</a>.</em></p>\n" \
              "<blockquote>\n" \
              "<h2>1.5.0 - June 2, 2015</h2>\n" \
              "<ul>\n" \
              "<li>Add 2016 holiday definitions</li>\n" \
              "</ul>\n" \
              "</blockquote>\n" \
              "</details>\n" \
              "#{commits_details(base: 'v1.4.0', head: 'v1.5.0')}" \
              "<br />\n\n" \
              "Updates `statesman` from 1.6.0 to 1.7.0\n" \
              "<details>\n" \
              "<summary>Changelog</summary>\n" \
              "<p><em>Sourced from <a href=\"https://github.com/gocardless/" \
              "statesman/blob/master/CHANGELOG.md\">" \
              "statesman's changelog</a>.</em></p>\n" \
              "<blockquote>\n" \
              "<h2>1.7.0 - January 18, 2017</h2>\n" \
              "<ul>\n" \
              "<li>Add 2018-2027 BACS holiday defintions</li>\n" \
              "</ul>\n" \
              "</blockquote>\n" \
              "</details>\n" \
              "<details>\n" \
              "<summary>Commits</summary>\n" \
              "<ul>\n" \
              "<li>See full diff in <a href=\"https://github.com/gocardless/" \
              "statesman/commits\">compare view</a></li>\n" \
              "</ul>\n" \
              "</details>\n" \
              "<br />\n"
            )
        end

        context "when for a property dependency (e.g., with Maven)" do
          before do
            statesman_repo_url =
              "https://api.github.com/repos/gocardless/statesman"
            stub_request(:get, "#{statesman_repo_url}/compare/v1.4.0...v1.5.0")
              .to_return(
                status: 200,
                body: fixture("github", "business_compare_commits.json"),
                headers: json_header
              )
          end

          let(:dependency) do
            Dependabot::Dependency.new(
              name: "business",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [{
                file: "Gemfile",
                requirement: "~> 1.5.0",
                groups: [],
                source: nil,
                metadata: { property_name: "springframework.version" }
              }],
              previous_requirements: [{
                file: "Gemfile",
                requirement: "~> 1.4.0",
                groups: [],
                source: nil,
                metadata: { property_name: "springframework.version" }
              }]
            )
          end
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "statesman",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [{
                file: "Gemfile",
                requirement: "~> 1.5.0",
                groups: [],
                source: nil,
                metadata: { property_name: "springframework.version" }
              }],
              previous_requirements: [{
                file: "Gemfile",
                requirement: "~> 1.4.0",
                groups: [],
                source: nil,
                metadata: { property_name: "springframework.version" }
              }]
            )
          end

          it "has the right intro" do
            expect(pr_message)
              .to start_with(
                "Bumps `springframework.version` from 1.4.0 to 1.5.0.\n"
              )
          end
        end
      end

      describe "removing a transitive dependency" do
        let(:dependencies) { [removed_dependency, dependency] }
        let(:removed_dependency) do
          Dependabot::Dependency.new(
            name: "statesman",
            previous_version: "1.6.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: [],
            removed: true
          )
        end

        it "includes details of both dependencies" do
          expect(pr_message)
            .to eq(
              "Removes [statesman](https://github.com/gocardless/statesman). It's no longer used after updating " \
              "ancestor dependency [business](https://github.com/gocardless/business). " \
              "These dependencies need to be updated together.\n\n" \
              "Removes `statesman`\n\n" \
              "Updates `business` from 1.4.0 to 1.5.0\n" \
              "<details>\n" \
              "<summary>Changelog</summary>\n" \
              "<p><em>Sourced from <a href=\"https://github.com/gocardless/" \
              "business/blob/master/CHANGELOG.md\">" \
              "business's changelog</a>.</em></p>\n" \
              "<blockquote>\n" \
              "<h2>1.5.0 - June 2, 2015</h2>\n" \
              "<ul>\n" \
              "<li>Add 2016 holiday definitions</li>\n" \
              "</ul>\n" \
              "</blockquote>\n" \
              "</details>\n" \
              "#{commits_details(base: 'v1.4.0', head: 'v1.5.0')}" \
              "<br />\n"
            )
        end
      end

      context "with multiple git source requirements", :vcr do
        include_context "with multiple git sources"

        it "has the correct message" do
          expect(pr_message).to start_with(
            "Updates the requirements on " \
            "[actions/checkout](https://github.com/gocardless/actions) " \
            "to permit the latest version."
          )
        end
      end

      context "when for a dependency group with 1 update", :vcr do
        let(:dependency_group) do
          Dependabot::DependencyGroup.new(name: "all-the-things", rules: { patterns: ["*"] })
        end

        let(:commit_message) { builder.commit_message }
        it "has the correct PR message" do
          expect(pr_message).to start_with(
            "Bumps the all-the-things group with 1 update: " \
            "[business](https://github.com/gocardless/business)."
          )
        end

        it "includes the version from -> to in the PR message" do
          expect(pr_message).to include(
            "from 1.4.0 to 1.5.0"
          )
        end

        it "has the correct commit message" do
          expect(commit_message).to start_with(
            "Bump business from 1.4.0 to 1.5.0 in the all-the-things group\n\n" \
            "Bumps the all-the-things group with 1 update: " \
            "[business](https://github.com/gocardless/business).\n\n\n" \
            "Updates `business` from 1.4.0 to 1.5.0"
          )
        end

        it "includes the version from -> to in the commit message" do
          expect(commit_message).to include(
            "from 1.4.0 to 1.5.0"
          )
        end

        context "with two dependencies" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business2",
              version: "1.8.0",
              previous_version: "1.7.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependencies) { [dependency, dependency2] }

          before do
            business2_repo_url =
              "https://api.github.com/repos/gocardless/business2"
            stub_request(:get, business2_repo_url)
              .to_return(status: 200,
                         body: fixture("github", "business_repo.json"),
                         headers: json_header)
            stub_request(:get, "#{business2_repo_url}/contents/")
              .to_return(status: 200,
                         body: fixture("github", "business_files.json"),
                         headers: json_header)
            stub_request(:get, "#{business2_repo_url}/releases?per_page=100")
              .to_return(status: 200,
                         body: fixture("github", "business_releases.json"),
                         headers: json_header)
            stub_request(:get, "https://api.github.com/repos/gocardless/" \
                               "business2/contents/CHANGELOG.md?ref=master")
              .to_return(status: 200,
                         body: fixture("github", "changelog_contents.json"),
                         headers: json_header)
            stub_request(:get, "https://rubygems.org/api/v1/gems/business2.json")
              .to_return(
                status: 200,
                body: fixture("ruby", "rubygems_response_statesman.json")
              )

            business2_service_pack_url =
              "https://github.com/gocardless/business2.git/info/refs" \
              "?service=git-upload-pack"
            stub_request(:get, business2_service_pack_url)
              .to_return(
                status: 200,
                body: fixture("git", "upload_packs", "no_tags"),
                headers: {
                  "content-type" => "application/x-git-upload-pack-advertisement"
                }
              )
          end

          it "has the correct PR message" do
            expect(pr_message).to start_with(
              "Bumps the all-the-things group with 2 updates: " \
              "[business](https://github.com/gocardless/business) and " \
              "[business2](https://github.com/gocardless/business2)."
            )
          end

          it "has the correct commit message" do
            expect(commit_message).to start_with(
              "Bump the all-the-things group with 2 updates\n\n" \
              "Bumps the all-the-things group with 2 updates: " \
              "[business](https://github.com/gocardless/business) and " \
              "[business2](https://github.com/gocardless/business2)."
            )
          end

          it "includes the versions from -> to in the commit message" do
            expect(commit_message).to include(
              "Updates `business` from 1.4.0 to 1.5.0"
            )
            expect(commit_message).to include(
              "Updates `business2` from 1.7.0 to 1.8.0"
            )
          end
        end

        context "with two dependencies with the same name" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependencies) { [dependency, dependency2] }

          it "has the correct message" do
            expect(pr_message).to start_with(
              "Bumps the all-the-things group with 1 update: " \
              "[business](https://github.com/gocardless/business)."
            )
          end
        end

        context "with three dependencies" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business2",
              version: "1.8.0",
              previous_version: "1.7.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency3) do
            Dependabot::Dependency.new(
              name: "business3",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependencies) { [dependency, dependency2, dependency3] }

          before do
            business2_repo_url =
              "https://api.github.com/repos/gocardless/business2"
            stub_request(:get, business2_repo_url)
              .to_return(status: 200,
                         body: fixture("github", "business_repo.json"),
                         headers: json_header)
            stub_request(:get, "#{business2_repo_url}/contents/")
              .to_return(status: 200,
                         body: fixture("github", "business_files.json"),
                         headers: json_header)
            stub_request(:get, "#{business2_repo_url}/releases?per_page=100")
              .to_return(status: 200,
                         body: fixture("github", "business_releases.json"),
                         headers: json_header)
            stub_request(:get, "https://api.github.com/repos/gocardless/" \
                               "business2/contents/CHANGELOG.md?ref=master")
              .to_return(status: 200,
                         body: fixture("github", "changelog_contents.json"),
                         headers: json_header)
            stub_request(:get, "https://rubygems.org/api/v1/gems/business2.json")
              .to_return(
                status: 200,
                body: fixture("ruby", "rubygems_response_statesman.json")
              )

            business2_service_pack_url =
              "https://github.com/gocardless/business2.git/info/refs" \
              "?service=git-upload-pack"
            stub_request(:get, business2_service_pack_url)
              .to_return(
                status: 200,
                body: fixture("git", "upload_packs", "no_tags"),
                headers: {
                  "content-type" => "application/x-git-upload-pack-advertisement"
                }
              )

            business3_repo_url =
              "https://api.github.com/repos/gocardless/business3"
            stub_request(:get, business3_repo_url)
              .to_return(status: 200,
                         body: fixture("github", "business_repo.json"),
                         headers: json_header)
            stub_request(:get, "#{business3_repo_url}/contents/")
              .to_return(status: 200,
                         body: fixture("github", "business_files.json"),
                         headers: json_header)
            stub_request(:get, "#{business3_repo_url}/releases?per_page=100")
              .to_return(status: 200,
                         body: fixture("github", "business_releases.json"),
                         headers: json_header)
            stub_request(:get, "https://api.github.com/repos/gocardless/" \
                               "business3/contents/CHANGELOG.md?ref=master")
              .to_return(status: 200,
                         body: fixture("github", "changelog_contents.json"),
                         headers: json_header)
            stub_request(:get, "https://rubygems.org/api/v1/gems/business3.json")
              .to_return(
                status: 200,
                body: fixture("ruby", "rubygems_response.json")
              )

            business3_service_pack_url =
              "https://github.com/gocardless/business3.git/info/refs" \
              "?service=git-upload-pack"
            stub_request(:get, business3_service_pack_url)
              .to_return(
                status: 200,
                body: fixture("git", "upload_packs", "no_tags"),
                headers: {
                  "content-type" => "application/x-git-upload-pack-advertisement"
                }
              )
          end

          it "has the correct message" do
            expect(pr_message).to start_with(
              "Bumps the all-the-things group with 3 updates: " \
              "[business](https://github.com/gocardless/business), " \
              "[business2](https://github.com/gocardless/business2) and " \
              "[business3](https://github.com/gocardless/business3)."
            )
          end
        end

        context "with five or more dependencies" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business2",
              version: "1.8.0",
              previous_version: "1.7.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency3) do
            Dependabot::Dependency.new(
              name: "business3",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency4) do
            Dependabot::Dependency.new(
              name: "business4",
              version: "2.1.1",
              previous_version: "2.1.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency5) do
            Dependabot::Dependency.new(
              name: "business5",
              version: "0.17.0",
              previous_version: "0.16.2",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependencies) { [dependency, dependency2, dependency3, dependency4, dependency5] }

          before do
            (2..5).each do |i|
              repo_url = "https://api.github.com/repos/gocardless/business#{i}"

              stub_request(:get, repo_url)
                .to_return(status: 200,
                           body: fixture("github", "business_repo.json"),
                           headers: json_header)
              stub_request(:get, "#{repo_url}/contents/")
                .to_return(status: 200,
                           body: fixture("github", "business_files.json"),
                           headers: json_header)
              stub_request(:get, "#{repo_url}/releases?per_page=100")
                .to_return(status: 200,
                           body: fixture("github", "business_releases.json"),
                           headers: json_header)
              stub_request(:get, "https://api.github.com/repos/gocardless/" \
                                 "business#{i}/contents/CHANGELOG.md?ref=master")
                .to_return(status: 200,
                           body: fixture("github", "changelog_contents.json"),
                           headers: json_header)
              stub_request(:get, "https://rubygems.org/api/v1/gems/business#{i}.json")
                .to_return(
                  status: 200,
                  body: fixture("ruby", "rubygems_response_statesman.json")
                )

              service_pack_url =
                "https://github.com/gocardless/business#{i}.git/info/refs" \
                "?service=git-upload-pack"

              stub_request(:get, service_pack_url)
                .to_return(
                  status: 200,
                  body: fixture("git", "upload_packs", "no_tags"),
                  headers: {
                    "content-type" => "application/x-git-upload-pack-advertisement"
                  }
                )
            end
          end

          it "has the correct message" do
            expect(pr_message).to start_with(
              "Bumps the all-the-things group with 5 updates:\n\n" \
              "| Package | From | To |\n" \
              "| --- | --- | --- |\n" \
              "| [business](https://github.com/gocardless/business) | `1.4.0` | `1.5.0` |\n" \
              "| [business2](https://github.com/gocardless/business2) | `1.7.0` | `1.8.0` |\n" \
              "| [business3](https://github.com/gocardless/business3) | `1.4.0` | `1.5.0` |\n" \
              "| [business4](https://github.com/gocardless/business4) | `2.1.0` | `2.1.1` |\n" \
              "| [business5](https://github.com/gocardless/business5) | `0.16.2` | `0.17.0` |"
            )
          end
        end

        context "with five or more dependencies with same name" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business2",
              version: "1.8.0",
              previous_version: "1.7.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency3) do
            Dependabot::Dependency.new(
              name: "business3",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency4) do
            Dependabot::Dependency.new(
              name: "business4",
              version: "2.1.1",
              previous_version: "2.1.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency5) do
            Dependabot::Dependency.new(
              name: "business5",
              version: "0.17.0",
              previous_version: "0.16.2",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency6) do
            Dependabot::Dependency.new(
              name: "business6",
              version: "0.5.4",
              previous_version: "0.4.2",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependencies) do
            [dependency, dependency2, dependency3, dependency4, dependency5, dependency5, dependency6]
          end

          before do
            (2..6).each do |i|
              repo_url = "https://api.github.com/repos/gocardless/business#{i}"

              stub_request(:get, repo_url)
                .to_return(status: 200,
                           body: fixture("github", "business_repo.json"),
                           headers: json_header)
              stub_request(:get, "#{repo_url}/contents/")
                .to_return(status: 200,
                           body: fixture("github", "business_files.json"),
                           headers: json_header)
              stub_request(:get, "#{repo_url}/releases?per_page=100")
                .to_return(status: 200,
                           body: fixture("github", "business_releases.json"),
                           headers: json_header)
              stub_request(:get, "https://api.github.com/repos/gocardless/" \
                                 "business#{i}/contents/CHANGELOG.md?ref=master")
                .to_return(status: 200,
                           body: fixture("github", "changelog_contents.json"),
                           headers: json_header)
              stub_request(:get, "https://rubygems.org/api/v1/gems/business#{i}.json")
                .to_return(
                  status: 200,
                  body: fixture("ruby", "rubygems_response_statesman.json")
                )

              service_pack_url =
                "https://github.com/gocardless/business#{i}.git/info/refs" \
                "?service=git-upload-pack"

              stub_request(:get, service_pack_url)
                .to_return(
                  status: 200,
                  body: fixture("git", "upload_packs", "no_tags"),
                  headers: {
                    "content-type" => "application/x-git-upload-pack-advertisement"
                  }
                )
            end
          end

          it "has the correct message" do
            expect(pr_message).to start_with(
              "Bumps the all-the-things group with 6 updates:\n\n" \
              "| Package | From | To |\n" \
              "| --- | --- | --- |\n" \
              "| [business](https://github.com/gocardless/business) | `1.4.0` | `1.5.0` |\n" \
              "| [business2](https://github.com/gocardless/business2) | `1.7.0` | `1.8.0` |\n" \
              "| [business3](https://github.com/gocardless/business3) | `1.4.0` | `1.5.0` |\n" \
              "| [business4](https://github.com/gocardless/business4) | `2.1.0` | `2.1.1` |\n" \
              "| [business5](https://github.com/gocardless/business5) | `0.16.2` | `0.17.0` |\n" \
              "| [business6](https://github.com/gocardless/business6) | `0.4.2` | `0.5.4` |\n\n" \
              "Updates `business` from 1.4.0 to 1.5.0"
            )
          end
        end

        context "with five or more dependencies with some duplicates" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business2",
              version: "1.8.0",
              previous_version: "1.7.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency3) do
            Dependabot::Dependency.new(
              name: "business3",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency4) do
            Dependabot::Dependency.new(
              name: "business4",
              version: "2.1.1",
              previous_version: "2.1.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency5) do
            Dependabot::Dependency.new(
              name: "business5",
              version: "0.17.0",
              previous_version: "0.16.2",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency6) do
            Dependabot::Dependency.new(
              name: "business6",
              version: "0.5.4",
              previous_version: "0.4.2",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency7) do
            Dependabot::Dependency.new(
              name: "business6",
              version: "0.5.4",
              previous_version: "0.4.2",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency8) do
            Dependabot::Dependency.new(
              name: "business6",
              version: "1.5.0",
              previous_version: "0.4.2",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependencies) do
            [dependency, dependency2, dependency3, dependency4, dependency5, dependency5, dependency6, dependency7,
             dependency8]
          end

          before do
            (2..6).each do |i|
              repo_url = "https://api.github.com/repos/gocardless/business#{i}"

              stub_request(:get, repo_url)
                .to_return(status: 200,
                           body: fixture("github", "business_repo.json"),
                           headers: json_header)
              stub_request(:get, "#{repo_url}/contents/")
                .to_return(status: 200,
                           body: fixture("github", "business_files.json"),
                           headers: json_header)
              stub_request(:get, "#{repo_url}/releases?per_page=100")
                .to_return(status: 200,
                           body: fixture("github", "business_releases.json"),
                           headers: json_header)
              stub_request(:get, "https://api.github.com/repos/gocardless/" \
                                 "business#{i}/contents/CHANGELOG.md?ref=master")
                .to_return(status: 200,
                           body: fixture("github", "changelog_contents.json"),
                           headers: json_header)
              stub_request(:get, "https://rubygems.org/api/v1/gems/business#{i}.json")
                .to_return(
                  status: 200,
                  body: fixture("ruby", "rubygems_response_statesman.json")
                )

              service_pack_url =
                "https://github.com/gocardless/business#{i}.git/info/refs" \
                "?service=git-upload-pack"

              stub_request(:get, service_pack_url)
                .to_return(
                  status: 200,
                  body: fixture("git", "upload_packs", "no_tags"),
                  headers: {
                    "content-type" => "application/x-git-upload-pack-advertisement"
                  }
                )
            end
          end

          it "has the correct message" do
            expect(pr_message).to start_with(
              "Bumps the all-the-things group with 7 updates:\n\n" \
              "| Package | From | To |\n" \
              "| --- | --- | --- |\n" \
              "| [business](https://github.com/gocardless/business) | `1.4.0` | `1.5.0` |\n" \
              "| [business2](https://github.com/gocardless/business2) | `1.7.0` | `1.8.0` |\n" \
              "| [business3](https://github.com/gocardless/business3) | `1.4.0` | `1.5.0` |\n" \
              "| [business4](https://github.com/gocardless/business4) | `2.1.0` | `2.1.1` |\n" \
              "| [business5](https://github.com/gocardless/business5) | `0.16.2` | `0.17.0` |\n" \
              "| [business6](https://github.com/gocardless/business6) | `0.4.2` | `0.5.4` |\n" \
              "| [business6](https://github.com/gocardless/business6) | `0.4.2` | `1.5.0` |\n\n" \
              "Updates `business` from 1.4.0 to 1.5.0"
            )
          end
        end

        context "with ignore conditions" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business2",
              version: "1.8.0",
              previous_version: "1.7.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency3) do
            Dependabot::Dependency.new(
              name: "business3",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency4) do
            Dependabot::Dependency.new(
              name: "business4",
              version: "2.1.1",
              previous_version: "2.1.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency5) do
            Dependabot::Dependency.new(
              name: "business5",
              version: "0.17.0",
              previous_version: "0.16.2",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependencies) { [dependency, dependency2, dependency3, dependency4, dependency5] }

          before do
            (2..5).each do |i|
              repo_url = "https://api.github.com/repos/gocardless/business#{i}"

              stub_request(:get, repo_url)
                .to_return(status: 200,
                           body: fixture("github", "business_repo.json"),
                           headers: json_header)
              stub_request(:get, "#{repo_url}/contents/")
                .to_return(status: 200,
                           body: fixture("github", "business_files.json"),
                           headers: json_header)
              stub_request(:get, "#{repo_url}/releases?per_page=100")
                .to_return(status: 200,
                           body: fixture("github", "business_releases.json"),
                           headers: json_header)
              stub_request(:get, "https://api.github.com/repos/gocardless/" \
                                 "business#{i}/contents/CHANGELOG.md?ref=master")
                .to_return(status: 200,
                           body: fixture("github", "changelog_contents.json"),
                           headers: json_header)
              stub_request(:get, "https://rubygems.org/api/v1/gems/business#{i}.json")
                .to_return(
                  status: 200,
                  body: fixture("ruby", "rubygems_response_statesman.json")
                )

              service_pack_url =
                "https://github.com/gocardless/business#{i}.git/info/refs" \
                "?service=git-upload-pack"

              stub_request(:get, service_pack_url)
                .to_return(
                  status: 200,
                  body: fixture("git", "upload_packs", "no_tags"),
                  headers: {
                    "content-type" => "application/x-git-upload-pack-advertisement"
                  }

                )
              ignore_conditions.push(
                {
                  "dependency-name" => "business#{i}",
                  "version-requirement" => "<= 1.#{i}.0",
                  "source" => "@dependabot ignore command",
                  "updated-at" => i == 4 ? nil : Time.now.iso8601
                }
              )
            end
          end

          it "has the correct message", focus: true do
            expect(pr_message).to include(
              "| Dependency Name | Ignore Conditions |\n" \
              "| --- | --- |\n" \
              "| business4 | [<= 1.4.0] |\n" \
              "| business2 | [<= 1.2.0] |\n" \
              "| business3 | [<= 1.3.0] |\n" \
              "| business5 | [<= 1.5.0] |\n"
            )
          end
        end

        context "without ignore conditions" do
          let(:dependency1) do
            Dependabot::Dependency.new(
              name: "business2",
              version: "1.8.0",
              previous_version: "1.7.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business3",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: []
            )
          end
          let(:dependencies) { [dependency1, dependency2] }

          before do
            (2..5).each do |i|
              repo_url = "https://api.github.com/repos/gocardless/business#{i}"

              stub_request(:get, repo_url)
                .to_return(status: 200,
                           body: fixture("github", "business_repo.json"),
                           headers: json_header)
              stub_request(:get, "#{repo_url}/contents/")
                .to_return(status: 200,
                           body: fixture("github", "business_files.json"),
                           headers: json_header)
              stub_request(:get, "#{repo_url}/releases?per_page=100")
                .to_return(status: 200,
                           body: fixture("github", "business_releases.json"),
                           headers: json_header)
              stub_request(:get, "https://api.github.com/repos/gocardless/" \
                                 "business#{i}/contents/CHANGELOG.md?ref=master")
                .to_return(status: 200,
                           body: fixture("github", "changelog_contents.json"),
                           headers: json_header)
              stub_request(:get, "https://rubygems.org/api/v1/gems/business#{i}.json")
                .to_return(
                  status: 200,
                  body: fixture("ruby", "rubygems_response_statesman.json")
                )

              service_pack_url =
                "https://github.com/gocardless/business#{i}.git/info/refs" \
                "?service=git-upload-pack"

              stub_request(:get, service_pack_url)
                .to_return(
                  status: 200,
                  body: fixture("git", "upload_packs", "no_tags"),
                  headers: {
                    "content-type" => "application/x-git-upload-pack-advertisement"
                  }
                )
            end
          end

          it "does not include the ignore conditions section in the message" do
            expect(pr_message).not_to include("Most Recent Ignore Conditions Applied to This Pull Request")
          end
        end

        context "with a directory specified" do
          let(:gemfile) do
            Dependabot::DependencyFile.new(
              name: "Gemfile",
              content: fixture("ruby", "gemfiles", "Gemfile"),
              directory: "directory"
            )
          end

          it "includes the directory" do
            expect(pr_message).to start_with(
              "Bumps the all-the-things group in /directory with 1 update: " \
              "[business](https://github.com/gocardless/business)."
            )
          end
        end
      end

      context "when for a multi-directory dependency group" do
        let(:source) do
          Dependabot::Source.new(provider: "github", repo: "gocardless/bump", directories: ["/foo", "/bar"])
        end
        let(:dependency_group) do
          Dependabot::DependencyGroup.new(name: "go_modules", rules: { patterns: ["*"] })
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            previous_version: "1.4.0",
            package_manager: "dummy",
            requirements: [],
            previous_requirements: [],
            metadata: { directory: "/foo" }
          )
        end

        it "has the correct message" do
          expect(pr_message).to start_with(
            "Bumps the go_modules group with 1 update in the /foo directory: " \
            "[business](https://github.com/gocardless/business)."
          )
        end

        it "includes the version from -> to" do
          expect(pr_message).to include(
            "from 1.4.0 to 1.5.0"
          )
        end

        context "with two dependencies in the same directory" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business2",
              version: "1.8.0",
              previous_version: "1.7.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: [],
              metadata: { directory: "/foo" }
            )
          end
          let(:dependencies) { [dependency, dependency2] }

          before do
            business2_repo_url =
              "https://api.github.com/repos/gocardless/business2"
            stub_request(:get, business2_repo_url)
              .to_return(status: 200,
                         body: fixture("github", "business_repo.json"),
                         headers: json_header)
            stub_request(:get, "#{business2_repo_url}/contents/")
              .to_return(status: 200,
                         body: fixture("github", "business_files.json"),
                         headers: json_header)
            stub_request(:get, "#{business2_repo_url}/releases?per_page=100")
              .to_return(status: 200,
                         body: fixture("github", "business_releases.json"),
                         headers: json_header)
            stub_request(:get, "https://api.github.com/repos/gocardless/" \
                               "business2/contents/CHANGELOG.md?ref=master")
              .to_return(status: 200,
                         body: fixture("github", "changelog_contents.json"),
                         headers: json_header)
            stub_request(:get, "https://rubygems.org/api/v1/gems/business2.json")
              .to_return(
                status: 200,
                body: fixture("ruby", "rubygems_response_statesman.json")
              )

            business2_service_pack_url =
              "https://github.com/gocardless/business2.git/info/refs" \
              "?service=git-upload-pack"
            stub_request(:get, business2_service_pack_url)
              .to_return(
                status: 200,
                body: fixture("git", "upload_packs", "no_tags"),
                headers: {
                  "content-type" => "application/x-git-upload-pack-advertisement"
                }
              )
          end

          it "has the correct message" do
            expect(pr_message).to start_with(
              "Bumps the go_modules group with 2 updates in the /foo directory: " \
              "[business](https://github.com/gocardless/business) and " \
              "[business2](https://github.com/gocardless/business2)."
            )
          end
        end

        context "with two dependencies in different directories" do
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business2",
              version: "1.8.0",
              previous_version: "1.7.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: [],
              metadata: { directory: "/bar" }
            )
          end
          let(:dependencies) { [dependency, dependency2] }

          before do
            business2_repo_url =
              "https://api.github.com/repos/gocardless/business2"
            stub_request(:get, business2_repo_url)
              .to_return(status: 200,
                         body: fixture("github", "business_repo.json"),
                         headers: json_header)
            stub_request(:get, "#{business2_repo_url}/contents/")
              .to_return(status: 200,
                         body: fixture("github", "business_files.json"),
                         headers: json_header)
            stub_request(:get, "#{business2_repo_url}/releases?per_page=100")
              .to_return(status: 200,
                         body: fixture("github", "business_releases.json"),
                         headers: json_header)
            stub_request(:get, "https://api.github.com/repos/gocardless/" \
                               "business2/contents/CHANGELOG.md?ref=master")
              .to_return(status: 200,
                         body: fixture("github", "changelog_contents.json"),
                         headers: json_header)
            stub_request(:get, "https://rubygems.org/api/v1/gems/business2.json")
              .to_return(
                status: 200,
                body: fixture("ruby", "rubygems_response_statesman.json")
              )

            business2_service_pack_url =
              "https://github.com/gocardless/business2.git/info/refs" \
              "?service=git-upload-pack"
            stub_request(:get, business2_service_pack_url)
              .to_return(
                status: 200,
                body: fixture("git", "upload_packs", "no_tags"),
                headers: {
                  "content-type" => "application/x-git-upload-pack-advertisement"
                }
              )
          end

          it "has the correct message" do
            expect(pr_message).to start_with(
              "Bumps the go_modules group with 1 update in the /foo directory: " \
              "[business](https://github.com/gocardless/business).\n" \
              "Bumps the go_modules group with 1 update in the /bar directory: " \
              "[business2](https://github.com/gocardless/business2)."
            )
          end
        end

        context "with table for one directory and no table for the other" do
          let(:dependencies2) do
            (1..5).map do |index|
              Dependabot::Dependency.new(
                name: "business#{index + 1}",
                version: "#{index + 1}.5.0",
                previous_version: "#{index + 1}.4.0",
                package_manager: "dummy",
                requirements: [],
                previous_requirements: [],
                metadata: { directory: "/bar" }
              )
            end
          end
          let(:dependencies) { dependencies2 + [dependency] }

          before do
            json_header = { "Content-Type" => "application/json" }

            stub_request(:get, %r{https://api\.github\.com/repos/gocardless/.+})
              .to_return(status: 200, body: fixture("github", "business_repo.json"), headers: json_header)
            stub_request(:get, %r{https://api\.github\.com/repos/gocardless/.+/contents/})
              .to_return(status: 200, body: fixture("github", "business_files.json"), headers: json_header)
            stub_request(:get, %r{https://api\.github\.com/repos/gocardless/.+/releases\?per_page=100})
              .to_return(status: 200, body: fixture("github", "business_releases.json"), headers: json_header)
            stub_request(:get, %r{https://api\.github\.com/repos/gocardless/.+/contents/CHANGELOG\.md\?ref=master})
              .to_return(status: 200, body: fixture("github", "changelog_contents.json"), headers: json_header)
            stub_request(:get, %r{https://rubygems\.org/api/v1/gems/.+\.json})
              .to_return(status: 200, body: fixture("ruby", "rubygems_response_statesman.json"))
            stub_request(:get, %r{https://github\.com/gocardless/.+\.git/info/refs\?service=git-upload-pack})
              .to_return(
                status: 200,
                body: fixture("git", "upload_packs", "no_tags"),
                headers: {
                  "content-type" => "application/x-git-upload-pack-advertisement"
                }
              )
          end

          it "has the correct message" do
            expect(pr_message).to include("Bumps the go_modules group with 1 update in the /foo directory: " \
                                          "[business](https://github.com/gocardless/business).\n" \
                                          "Bumps the go_modules group with 5 updates in the /bar directory:\n\n" \
                                          "| Package | From | To |\n" \
                                          "| --- | --- | --- |\n" \
                                          "| [business2]")
          end

          context "when one of the dependencies in the table is removed" do
            let(:removed_dependency) do
              Dependabot::Dependency.new(
                name: "business_removed",
                version: nil,
                previous_version: "1.7.0",
                package_manager: "dummy",
                requirements: [],
                previous_requirements: [],
                metadata: { directory: "/bar" },
                removed: true
              )
            end

            before do
              dependencies2.push(removed_dependency)
            end

            it "lists the dependency as removed in the table" do
              expect(pr_message).to include(
                "| [business_removed](https://github.com/gocardless/business_removed) | `1.7.0` | `removed` |"
              )
            end
          end
        end

        context "with table for one directory come first and no table for the other" do
          let(:dependencies1) do
            (1..5).map do |index|
              Dependabot::Dependency.new(
                name: "business#{index + 1}",
                version: "#{index + 1}.5.0",
                previous_version: "#{index + 1}.4.0",
                package_manager: "dummy",
                requirements: [],
                previous_requirements: [],
                metadata: { directory: "/foo" }
              )
            end
          end
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "business2",
              version: "1.8.0",
              previous_version: "1.7.0",
              package_manager: "dummy",
              requirements: [],
              previous_requirements: [],
              metadata: { directory: "/bar" }
            )
          end
          let(:dependencies) { dependencies1 + [dependency] + [dependency2] }

          before do
            json_header = { "Content-Type" => "application/json" }

            stub_request(:get, %r{https://api\.github\.com/repos/gocardless/.+})
              .to_return(status: 200, body: fixture("github", "business_repo.json"), headers: json_header)
            stub_request(:get, %r{https://api\.github\.com/repos/gocardless/.+/contents/})
              .to_return(status: 200, body: fixture("github", "business_files.json"), headers: json_header)
            stub_request(:get, %r{https://api\.github\.com/repos/gocardless/.+/releases\?per_page=100})
              .to_return(status: 200, body: fixture("github", "business_releases.json"), headers: json_header)
            stub_request(:get, %r{https://api\.github\.com/repos/gocardless/.+/contents/CHANGELOG\.md\?ref=master})
              .to_return(status: 200, body: fixture("github", "changelog_contents.json"), headers: json_header)
            stub_request(:get, %r{https://rubygems\.org/api/v1/gems/.+\.json})
              .to_return(status: 200, body: fixture("ruby", "rubygems_response_statesman.json"))
            stub_request(:get, %r{https://github\.com/gocardless/.+\.git/info/refs\?service=git-upload-pack})
              .to_return(
                status: 200,
                body: fixture("git", "upload_packs", "no_tags"),
                headers: {
                  "content-type" => "application/x-git-upload-pack-advertisement"
                }
              )
          end

          it "has the correct message" do
            expected_message = "Bumps the go_modules group with 6 updates in the /foo directory:\n\n" \
                               "| Package | From | To |\n" \
                               "| --- | --- | --- |\n" \
                               "| [business2](https://github.com/gocardless/business2) | `2.4.0` | `2.5.0` |\n" \
                               "| [business3](https://github.com/gocardless/business3) | `3.4.0` | `3.5.0` |\n" \
                               "| [business4](https://github.com/gocardless/business4) | `4.4.0` | `4.5.0` |\n" \
                               "| [business5](https://github.com/gocardless/business5) | `5.4.0` | `5.5.0` |\n" \
                               "| [business6](https://github.com/gocardless/business6) | `6.4.0` | `6.5.0` |\n" \
                               "| [business](https://github.com/gocardless/business) | `1.4.0` | `1.5.0` |\n\n" \
                               "Bumps the go_modules group with 1 update in the /bar directory: [business2](https://github.com/gocardless/business2)."

            expect(pr_message).to include(expected_message)
          end
        end

        context "with a table for both directories" do
          let(:dependencies1) do
            (1..5).map do |index|
              Dependabot::Dependency.new(
                name: "business#{index + 1}",
                version: "#{index + 1}.5.0",
                previous_version: "#{index + 1}.4.0",
                package_manager: "dummy",
                requirements: [],
                previous_requirements: [],
                metadata: { directory: "/foo" }
              )
            end
          end
          let(:dependencies2) do
            (1..5).map do |index|
              Dependabot::Dependency.new(
                name: "business#{index + 1}",
                version: "#{index + 1}.5.0",
                previous_version: "#{index + 1}.4.0",
                package_manager: "dummy",
                requirements: [],
                previous_requirements: [],
                metadata: { directory: "/bar" }
              )
            end
          end
          let(:dependencies) { dependencies1 + dependencies2 + [dependency] }

          before do
            json_header = { "Content-Type" => "application/json" }

            stub_request(:get, %r{https://api\.github\.com/repos/gocardless/.+})
              .to_return(status: 200, body: fixture("github", "business_repo.json"), headers: json_header)
            stub_request(:get, %r{https://api\.github\.com/repos/gocardless/.+/contents/})
              .to_return(status: 200, body: fixture("github", "business_files.json"), headers: json_header)
            stub_request(:get, %r{https://api\.github\.com/repos/gocardless/.+/releases\?per_page=100})
              .to_return(status: 200, body: fixture("github", "business_releases.json"), headers: json_header)
            stub_request(:get, %r{https://api\.github\.com/repos/gocardless/.+/contents/CHANGELOG\.md\?ref=master})
              .to_return(status: 200, body: fixture("github", "changelog_contents.json"), headers: json_header)
            stub_request(:get, %r{https://rubygems\.org/api/v1/gems/.+\.json})
              .to_return(status: 200, body: fixture("ruby", "rubygems_response_statesman.json"))
            stub_request(:get, %r{https://github\.com/gocardless/.+\.git/info/refs\?service=git-upload-pack})
              .to_return(
                status: 200,
                body: fixture("git", "upload_packs", "no_tags"),
                headers: {
                  "content-type" => "application/x-git-upload-pack-advertisement"
                }
              )
          end

          it "has the correct message" do
            expected_message = "Bumps the go_modules group with 6 updates in the /foo directory:\n\n" \
                               "| Package | From | To |\n" \
                               "| --- | --- | --- |\n" \
                               "| [business2](https://github.com/gocardless/business2) | `2.4.0` | `2.5.0` |\n" \
                               "| [business3](https://github.com/gocardless/business3) | `3.4.0` | `3.5.0` |\n" \
                               "| [business4](https://github.com/gocardless/business4) | `4.4.0` | `4.5.0` |\n" \
                               "| [business5](https://github.com/gocardless/business5) | `5.4.0` | `5.5.0` |\n" \
                               "| [business6](https://github.com/gocardless/business6) | `6.4.0` | `6.5.0` |\n" \
                               "| [business](https://github.com/gocardless/business) | `1.4.0` | `1.5.0` |\n\n" \
                               "Bumps the go_modules group with 5 updates in the /bar directory:\n\n" \
                               "| Package | From | To |\n" \
                               "| --- | --- | --- |\n" \
                               "| [business2](https://github.com/gocardless/business2) | `2.4.0` | `2.5.0` |\n" \
                               "| [business3](https://github.com/gocardless/business3) | `3.4.0` | `3.5.0` |\n" \
                               "| [business4](https://github.com/gocardless/business4) | `4.4.0` | `4.5.0` |\n" \
                               "| [business5](https://github.com/gocardless/business5) | `5.4.0` | `5.5.0` |\n" \
                               "| [business6](https://github.com/gocardless/business6) | `6.4.0` | `6.5.0`"

            expect(pr_message).to include(expected_message)
          end
        end
      end
    end

    context "when for a library" do
      let(:files) { [gemfile, gemfile_lock, gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          name: "bump.gemspec",
          content: fixture("ruby", "gemspecs", "example")
        )
      end

      it "has the right text" do
        expect(pr_message)
          .to eq(
            "Updates the requirements on " \
            "[business](https://github.com/gocardless/business) " \
            "to permit the latest version.\n" \
            "<details>\n" \
            "<summary>Changelog</summary>\n" \
            "<p><em>Sourced from " \
            "<a href=\"https://github.com/gocardless/business/blob/master/" \
            "CHANGELOG.md\">business's changelog</a>.</em></p>\n" \
            "<blockquote>\n" \
            "<h2>1.5.0 - June 2, 2015</h2>\n" \
            "<ul>\n" \
            "<li>Add 2016 holiday definitions</li>\n" \
            "</ul>\n" \
            "</blockquote>\n" \
            "</details>\n" \
            "#{commits_details(base: 'v1.4.0', head: 'v1.5.0')}" \
            "<br />\n"
          )
      end

      context "when updating multiple dependencies" do
        let(:dependencies) { [dependency, dependency2] }
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "statesman",
            version: "1.7.0",
            previous_version: "1.6.0",
            package_manager: "dummy",
            requirements: [{
              file: "Gemfile",
              requirement: "~> 1.7",
              groups: [],
              source: nil
            }],
            previous_requirements: [{
              file: "Gemfile",
              requirement: "~> 1.6",
              groups: [],
              source: nil
            }]
          )
        end

        before do
          statesman_repo_url =
            "https://api.github.com/repos/gocardless/statesman"
          stub_request(:get, statesman_repo_url)
            .to_return(status: 200,
                       body: fixture("github", "statesman_repo.json"),
                       headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/contents/")
            .to_return(status: 200,
                       body: fixture("github", "statesman_files.json"),
                       headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/releases?per_page=100")
            .to_return(status: 200,
                       body: fixture("github", "business_releases.json"),
                       headers: json_header)
          stub_request(:get, "https://api.github.com/repos/gocardless/" \
                             "statesman/contents/CHANGELOG.md?ref=master")
            .to_return(status: 200,
                       body: fixture("github", "changelog_contents.json"),
                       headers: json_header)
          stub_request(:get, "https://rubygems.org/api/v1/gems/statesman.json")
            .to_return(
              status: 200,
              body: fixture("ruby", "rubygems_response_statesman.json")
            )

          service_pack_url =
            "https://github.com/gocardless/statesman.git/info/refs" \
            "?service=git-upload-pack"
          stub_request(:get, service_pack_url)
            .to_return(
              status: 200,
              body: fixture("git", "upload_packs", "no_tags"),
              headers: {
                "content-type" => "application/x-git-upload-pack-advertisement"
              }
            )
        end

        it "includes details of both dependencies" do
          expect(pr_message)
            .to eq(
              "Updates the requirements on " \
              "[business](https://github.com/gocardless/business) " \
              "and [statesman](https://github.com/gocardless/statesman) " \
              "to permit the latest version.\n" \
              "Updates `business` from 1.4.0 to 1.5.0\n" \
              "<details>\n" \
              "<summary>Changelog</summary>\n" \
              "<p><em>Sourced from <a href=\"https://github.com/gocardless/" \
              "business/blob/master/CHANGELOG.md\">" \
              "business's changelog</a>.</em></p>\n" \
              "<blockquote>\n" \
              "<h2>1.5.0 - June 2, 2015</h2>\n" \
              "<ul>\n" \
              "<li>Add 2016 holiday definitions</li>\n" \
              "</ul>\n" \
              "</blockquote>\n" \
              "</details>\n" \
              "#{commits_details(base: 'v1.4.0', head: 'v1.5.0')}" \
              "<br />\n\n" \
              "Updates `statesman` from 1.6.0 to 1.7.0\n" \
              "<details>\n" \
              "<summary>Changelog</summary>\n" \
              "<p><em>Sourced from <a href=\"https://github.com/gocardless/" \
              "statesman/blob/master/CHANGELOG.md\">" \
              "statesman's changelog</a>.</em></p>\n" \
              "<blockquote>\n" \
              "<h2>1.7.0 - January 18, 2017</h2>\n" \
              "<ul>\n" \
              "<li>Add 2018-2027 BACS holiday defintions</li>\n" \
              "</ul>\n" \
              "</blockquote>\n" \
              "</details>\n" \
              "<details>\n" \
              "<summary>Commits</summary>\n" \
              "<ul>\n" \
              "<li>See full diff in <a href=\"https://github.com/gocardless/" \
              "statesman/commits\">compare view</a></li>\n" \
              "</ul>\n" \
              "</details>\n" \
              "<br />\n"
            )
        end
      end
    end

    context "with a footer" do
      let(:pr_message_footer) { "I'm a footer!" }

      it { is_expected.to end_with("\n\nI'm a footer!") }
    end

    context "with a header" do
      let(:pr_message_header) { "I'm a header!" }

      it { is_expected.to start_with("I'm a header!\n\n") }
    end

    context "with author details" do
      let(:signoff_details) do
        {
          email: "support@dependabot.com",
          name: "dependabot"
        }
      end

      it "doesn't include a signoff line" do
        expect(pr_message).to_not include("Signed-off-by")
      end
    end

    context "with custom traier" do
      let(:trailers) { { "Changelog" => "dependency" } }

      it "doesn't include git trailer" do
        expect(pr_message).to_not include("Changelog: dependency")
      end
    end
  end

  describe "#commit_message", :vcr do
    subject(:commit_message) { builder.commit_message }

    let(:expected_commit_message) do
      <<~MSG.chomp
        Bump business from 1.4.0 to 1.5.0

        Bumps [business](https://github.com/gocardless/business) from 1.4.0 to 1.5.0.
        - [Release notes](https://github.com/gocardless/business/releases)
        - [Changelog](https://github.com/gocardless/business/blob/master/CHANGELOG.md)
        - [Commits](https://github.com/gocardless/business/compare/v1.4.0...v1.5.0)
      MSG
    end

    it "renders the expected message" do
      is_expected.to eql(expected_commit_message)
    end

    context "with a PR name that is too long" do
      before do
        allow(builder).to receive(:pr_name)
          .and_return(
            "build(deps-dev): update postcss-import requirement from " \
            "^11.1.0 to ^12.0.0 in /electron"
          )
      end

      it "truncates the subject line sensibly" do
        expect(commit_message)
          .to start_with(
            "build(deps-dev): update postcss-import requirement in /electron\n"
          )
      end

      describe "and the directory needs to be truncated, too" do
        before do
          allow(builder).to receive(:pr_name)
            .and_return(
              "build(deps-dev): update postcss-import requirement from " \
              "^11.1.0 to ^12.0.0 in /electron-really-long-name"
            )
        end

        it "truncates the subject line sensibly" do
          expect(commit_message)
            .to start_with(
              "build(deps-dev): update postcss-import requirement\n"
            )
        end
      end
    end

    context "with author details" do
      let(:signoff_details) do
        {
          email: "support@dependabot.com",
          name: "dependabot"
        }
      end

      it "includes a signoff line" do
        expect(commit_message)
          .to end_with("\n\nSigned-off-by: dependabot <support@dependabot.com>")
      end

      context "when that includes org details" do
        let(:signoff_details) do
          {
            email: "support@dependabot.com",
            name: "dependabot",
            org_email: "support@tutum.com",
            org_name: "tutum"
          }
        end

        it "includes an on-behalf-of line" do
          expect(commit_message).to end_with(
            "\n\nOn-behalf-of: @tutum <support@tutum.com>\n" \
            "Signed-off-by: dependabot <support@dependabot.com>"
          )
        end
      end
    end

    context "with single custom trailer" do
      let(:trailers) { { "Changelog" => "dependency" } }

      it "includes custom trailer" do
        expect(commit_message).to end_with("\n\nChangelog: dependency")
      end

      context "with author details" do
        let(:signoff_details) do
          {
            email: "support@dependabot.com",
            name: "dependabot"
          }
        end

        it "includes custom trailer and signoff line" do
          expect(commit_message)
            .to end_with("\n\nSigned-off-by: dependabot <support@dependabot.com>\nChangelog: dependency")
        end
      end
    end

    context "with multiple trailers" do
      let(:trailers) { { "Changelog" => "dependency", "Helped-by" => "dependabot" } }

      it "includes custom trailers" do
        expect(commit_message).to end_with("\n\n#{trailers.map { |k, v| "#{k}: #{v}" }.join("\n")}")
      end
    end

    context "with incorrect trailers format" do
      let(:trailers) { "Changelog: dependency" }

      it "raises error" do
        expect { commit_message }.to raise_error("Commit trailers must be a Hash object")
      end
    end

    context "when for a repo that uses gitmoji commits" do
      before do
        allow(builder).to receive(:pr_name).and_call_original
        stub_request(:get, watched_repo_url + "/commits?per_page=100")
          .to_return(status: 200,
                     body: fixture("github", "commits_gitmoji.json"),
                     headers: json_header)
      end

      it "uses gitmoji" do
        is_expected.to start_with(":arrow_up: Bump ")
      end

      context "with a security vulnerability fixed" do
        let(:vulnerabilities_fixed) { { business: [{}] } }
        it "uses gitmoji" do
          is_expected.to start_with(":arrow_up::lock: Bump ")
        end
      end
    end
  end

  describe "#message" do
    subject(:message) { builder.message }

    pr_name = "PR title"
    pr_message = "PR message"
    commit_message = "Commit message"
    before do
      allow(builder).to receive(:pr_name).and_return(pr_name)
      allow(builder).to receive(:pr_message).and_return(pr_message)
      allow(builder).to receive(:commit_message).and_return(commit_message)
    end

    it "returns a Message" do
      expect(message).to be_a(Dependabot::PullRequestCreator::Message)
    end
    its(:pr_name) { should eq(pr_name) }
    its(:pr_message) { should eq(pr_message) }
    its(:commit_message) { should eq(commit_message) }
  end

  subject(:message_builder) { builder }
  describe "#truncate_pr_message" do
    context "when pr_message_max_length is not provided" do
      let(:message) { "This is a normal length PR description and it should not be truncated." }

      it "returns the original message" do
        expect(message_builder.truncate_pr_message(message)).to eq(message)
      end

      let(:message) { "This is a test message with special characters: © ®" }

      it "returns the original encoding of the message" do
        message_builder.pr_message_encoding = Encoding::UTF_16
        expect(message_builder.truncate_pr_message(message)).to eq(message)
      end
    end

    context "when pr_message_max_length is provided" do
      let(:message) { "A" * 10_250 } # Exceeds the maximum length of 10,239
      let(:pr_message_max_length) { 10_239 }

      it "truncates the message to the specified length" do
        truncated_msg = "...\n\n_Description has been truncated_"
        truncate_length = pr_message_max_length - truncated_msg.length
        expected_truncated_description = "#{message[0..truncate_length]}#{truncated_msg}"

        message_builder.pr_message_max_length = pr_message_max_length
        expect(message_builder.truncate_pr_message(message)).to eq(expected_truncated_description)
      end

      let(:message) { "© ®" * 100 } # Exceeds the maximum length of 100
      let(:pr_message_max_length) { 100 }

      it "truncates and maintains the specified encoding" do
        encode_utf16 = Encoding::UTF_16
        msg = message.dup.force_encoding(encode_utf16)
        trunc_msg = (+"...\n\n_Description has been truncated_").force_encoding(encode_utf16)
        trunc_length = pr_message_max_length - trunc_msg.length
        msg = "#{msg[0..trunc_length]}#{trunc_msg}"
        msg = msg.encode("utf-8", "binary", invalid: :replace, undef: :replace)

        message_builder.pr_message_max_length = pr_message_max_length
        message_builder.pr_message_encoding = encode_utf16
        expect(message_builder.truncate_pr_message(message)).to eq(msg)

        # ensure we can work convert to JSON (uses UTF-8 by default)
        # this matches what happens in the azure client when creating a pull request
        expect({ description: msg }.to_json)
          .to start_with("{\"description\":\"")
          .and end_with("\\n\\n_Description has been truncated_\"}")
      end
    end

    context "when the pull request description is an empty string" do
      let(:message) { "" }
      let(:pr_message_max_length) { 100 }

      it "returns an empty string" do
        message_builder.pr_message_max_length = pr_message_max_length
        expect(message_builder.truncate_pr_message(message)).to eq("")
      end

      it "returns an empty string when encoded" do
        message_builder.pr_message_max_length = pr_message_max_length
        message_builder.pr_message_encoding = Encoding::UTF_16
        expect(message_builder.truncate_pr_message(message)).to eq("")
      end
    end
  end
end
