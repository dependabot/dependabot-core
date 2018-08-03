# frozen_string_literal: true

require "octokit"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pull_request_creator/message_builder"

RSpec.describe Dependabot::PullRequestCreator::MessageBuilder do
  subject(:builder) do
    described_class.new(
      source: source,
      dependencies: dependencies,
      files: files,
      credentials: credentials,
      pr_message_footer: pr_message_footer,
      author_details: author_details,
      vulnerabilities_fixed: vulnerabilities_fixed
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
      package_manager: "bundler",
      requirements:
        [{ file: "Gemfile", requirement: "~> 1.5.0", groups: [], source: nil }],
      previous_requirements:
        [{ file: "Gemfile", requirement: "~> 1.4.0", groups: [], source: nil }]
    )
  end
  let(:files) { [gemfile, gemfile_lock] }
  let(:credentials) do
    [{
      "type" => "git_source",
      "host" => "github.com",
      "username" => "x-access-token",
      "password" => "token"
    }]
  end
  let(:pr_message_footer) { nil }
  let(:author_details) { nil }
  let(:vulnerabilities_fixed) { { "business" => [] } }

  let(:gemfile) do
    Dependabot::DependencyFile.new(
      name: "Gemfile",
      content: fixture("ruby", "gemfiles", "Gemfile")
    )
  end
  let(:gemfile_lock) do
    Dependabot::DependencyFile.new(
      name: "Gemfile.lock",
      content: fixture("ruby", "lockfiles", "Gemfile.lock")
    )
  end

  let(:json_header) { { "Content-Type" => "application/json" } }
  let(:watched_repo_url) { "https://api.github.com/repos/#{source.repo}" }

  def commits_details(base:, head:)
    "<details>\n"\
    "<summary>Commits</summary>\n\n"\
    "- [`26f4887`](https://github.com/gocardless/business/commit/"\
    "26f4887ec647493f044836363537e329d9d213aa) Bump version to v1.4.0\n"\
    "- [`7abe4c2`](https://github.com/gocardless/business/commit/"\
    "7abe4c2dc0161904c40c221a48999d12995fbea7) "\
    "Merge pull request [#9](https://github-redirect.dependabot.com/"\
    "gocardless/business/issues/9) from gocardless/custom-calendars\n"\
    "- [`1c72c35`](https://github.com/gocardless/business/commit/"\
    "1c72c35ff2aa9d7ce0403d7fd4aa010d94723076) Allow custom calendars\n"\
    "- [`0bfb8c3`](https://github.com/gocardless/business/commit/"\
    "0bfb8c3f0d2701abf9248185beeb8adf643374f6) Spacing\n"\
    "- [`a5970da`](https://github.com/gocardless/business/commit/"\
    "a5970daf0b824e4c3974e57474b6cf9e39a11d0f) "\
    "Merge pull request [#8](https://github-redirect.dependabot.com/"\
    "gocardless/business/issues/8) from gocardless/rename-sepa-to-ecb\n"\
    "- [`d2eb29b`](https://github.com/gocardless/business/commit/"\
    "d2eb29beda934c14220146c82f830de2edd63a25) "\
    "Remove SEPA calendar (replaced by TARGET)\n"\
    "- See full diff in [compare view](https://github.com/gocardless/business/"\
    "compare/#{base}...#{head})\n"\
    "</details>\n"
  end

  describe "#pr_name" do
    subject(:pr_name) { builder.pr_name }

    context "for an application" do
      context "that doesn't use semantic commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits").
            to_return(
              status: 200,
              body: commits_response,
              headers: json_header
            )
        end
        let(:commits_response) { fixture("github", "commits.json") }

        it { is_expected.to eq("Bump business from 1.4.0 to 1.5.0") }

        context "from GitLab" do
          let(:source) do
            Dependabot::Source.new(provider: "gitlab", repo: "gocardless/bump")
          end
          let(:watched_repo_url) do
            "https://gitlab.com/api/v4/projects/"\
            "#{CGI.escape(source.repo)}/repository"
          end
          let(:commits_response) { fixture("gitlab", "commits.json") }

          it { is_expected.to eq("Bump business from 1.4.0 to 1.5.0") }
        end

        context "with a security vulnerability fixed" do
          let(:vulnerabilities_fixed) { { "business": [{}] } }
          it { is_expected.to start_with("[Security] Bump business") }
        end

        context "with two dependencies" do
          let(:dependencies) { [dependency, dependency] }
          it { is_expected.to eq("Bump business and business") }

          context "for Maven" do
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
            let(:pom) do
              Dependabot::DependencyFile.new(
                name: "pom.xml",
                content: fixture("java", "poms", "property_pom.xml")
              )
            end
            let(:files) { [pom] }

            it "has the right name" do
              expect(pr_name).
                to eq(
                  "Bump springframework.version "\
                  "from 4.3.12.RELEASE to 4.3.15.RELEASE"
                )
            end
          end
        end

        context "with three dependencies" do
          let(:dependencies) { [dependency, dependency, dependency] }
          it { is_expected.to eq("Bump business, business and business") }
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
            expect(pr_name).
              to eq("Bump business from 1.4.0 to 1.5.0 in /directory")
          end
        end

        context "with SHA-1 versions" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "business",
              version: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2",
              previous_version: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
              package_manager: "bundler",
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

          context "due to a ref change" do
            let(:new_ref) { "v1.1.0" }
            let(:old_ref) { "v1.0.0" }

            it "uses the refs" do
              expect(pr_name).to eq("Bump business from v1.0.0 to v1.1.0")
            end
          end
        end
      end

      context "that uses semantic commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits").
            to_return(status: 200,
                      body: fixture("github", "commits_semantic.json"),
                      headers: json_header)
        end

        it do
          is_expected.to eq("build(deps): bump business from 1.4.0 to 1.5.0")
        end

        context "with a security vulnerability fixed" do
          let(:vulnerabilities_fixed) { { "business": [{}] } }
          it { is_expected.to start_with("build(deps): [security] bump") }
        end

        context "with a dev dependency" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "business",
              version: "1.5.0",
              previous_version: "1.4.0",
              package_manager: "bundler",
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

          it { is_expected.to start_with("build(deps-dev): bump") }
        end
      end

      context "that uses gitmoji commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits").
            to_return(status: 200,
                      body: fixture("github", "commits_gitmoji.json"),
                      headers: json_header)
        end

        it { is_expected.to eq("⬆️ Bump business from 1.4.0 to 1.5.0") }

        context "with a security vulnerability fixed" do
          let(:vulnerabilities_fixed) { { "business": [{}] } }
          it { is_expected.to start_with("⬆️ 🔒 Bump") }
        end
      end
    end

    context "for a library" do
      let(:files) { [gemfile, gemfile_lock, gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          name: "bump.gemspec",
          content: fixture("ruby", "gemspecs", "example")
        )
      end

      context "that doesn't use semantic commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits").
            to_return(status: 200, body: "[]", headers: json_header)
        end

        it "has the right title" do
          expect(pr_name).
            to eq("Update business requirement from ~> 1.4.0 to ~> 1.5.0")
        end

        context "with a security vulnerability fixed" do
          let(:vulnerabilities_fixed) { { "business": [{}] } }
          it { is_expected.to start_with("[Security] Update business") }
        end

        context "with two dependencies" do
          let(:dependencies) { [dependency, dependency] }

          it "includes both dependencies" do
            expect(pr_name).
              to eq("Update requirements for business and business")
          end
        end

        context "with three dependencies" do
          let(:dependencies) { [dependency, dependency, dependency] }

          it "includes all three dependencies" do
            expect(pr_name).
              to eq("Update requirements for business, business and business")
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
            expect(pr_name).
              to eq("Update business requirement from ~> 1.4.0 to ~> 1.5.0 "\
                    "in /directory")
          end
        end
      end

      context "that uses semantic commits" do
        before do
          stub_request(:get, watched_repo_url + "/commits").
            to_return(status: 200,
                      body: fixture("github", "commits_semantic.json"),
                      headers: json_header)
        end

        it "uses a semantic commit prefix" do
          expect(pr_name).
            to eq("build(deps): update business requirement from ~> 1.4.0 "\
                  "to ~> 1.5.0")
        end

        context "with a security vulnerability fixed" do
          let(:vulnerabilities_fixed) { { "business": [{}] } }
          it { is_expected.to start_with("build(deps): [security] update") }
        end
      end
    end
  end

  describe "#pr_message" do
    subject(:pr_message) { builder.pr_message }

    let(:business_repo_url) do
      "https://api.github.com/repos/gocardless/business"
    end

    before do
      stub_request(:get, watched_repo_url + "/commits").
        to_return(status: 200, body: "[]", headers: json_header)

      stub_request(:get, business_repo_url).
        to_return(status: 200,
                  body: fixture("github", "business_repo.json"),
                  headers: json_header)
      stub_request(:get, "#{business_repo_url}/contents/").
        to_return(status: 200,
                  body: fixture("github", "business_files.json"),
                  headers: json_header)
      stub_request(:get, "#{business_repo_url}/tags?per_page=100").
        to_return(status: 200,
                  body: fixture("github", "business_tags.json"),
                  headers: json_header)
      stub_request(:get, "#{business_repo_url}/releases?per_page=100").
        to_return(status: 200,
                  body: fixture("github", "business_releases.json"),
                  headers: json_header)
      stub_request(:get, "https://api.github.com/repos/gocardless/"\
                         "business/contents/CHANGELOG.md").
        to_return(status: 200,
                  body: fixture("github", "changelog_contents.json"),
                  headers: json_header)
      stub_request(:get, "#{business_repo_url}/compare/v1.4.0...v1.5.0").
        to_return(status: 200,
                  body: fixture("github", "business_compare_commits.json"),
                  headers: json_header)
      stub_request(:get, "https://rubygems.org/api/v1/gems/business.json").
        to_return(status: 200, body: fixture("ruby", "rubygems_response.json"))
    end

    context "for an application" do
      it "has the right text" do
        expect(pr_message).
          to eq(
            "Bumps [business](https://github.com/gocardless/business) "\
            "from 1.4.0 to 1.5.0.\n"\
            "<details>\n"\
            "<summary>Changelog</summary>\n\n"\
            "*Sourced from [business's changelog](https://github.com/"\
            "gocardless/business/blob/master/CHANGELOG.md).*\n\n"\
            "> ## 1.5.0 - June 2, 2015\n"\
            "> \n"\
            "> - Add 2016 holiday definitions\n"\
            "</details>\n"\
            "#{commits_details(base: 'v1.4.0', head: 'v1.5.0')}"\
            "<br />"
          )
      end

      context "with SHA-1 versions" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2",
            previous_version: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
            package_manager: "bundler",
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

        before do
          stub_request(
            :get,
            "https://api.github.com/repos/gocardless/business/compare/"\
            "2468a02a6230e59ed1232d95d1ad3ef157195b03..."\
            "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2"
          ).with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "business_compare_commits.json"),
              headers: { "Content-Type" => "application/json" }
            )
        end

        it "has the right text" do
          commits_details = commits_details(
            base: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
            head: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2"
          )
          expect(pr_message).to eq(
            "Bumps [business](https://github.com/gocardless/business) "\
            "from `2468a02` to `cff701b`.\n"\
            "#{commits_details}"\
            "<br />"
          )
        end

        context "due to a ref change" do
          let(:new_ref) { "v1.1.0" }
          let(:old_ref) { "v1.0.0" }

          it "has the right text" do
            commits_details = commits_details(
              base: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
              head: "cff701b3bfb182afc99a85657d7c9f3d6c1ccce2"
            )
            expect(pr_message).
              to eq(
                "Bumps [business](https://github.com/gocardless/business) "\
                "from v1.0.0 to v1.1.0.\n"\
                "<details>\n"\
                "<summary>Changelog</summary>\n\n"\
                "*Sourced from [business's changelog](https://github.com/"\
                "gocardless/business/blob/master/CHANGELOG.md).*\n\n"\
                "> ## 1.1.0 - September 30, 2014\n"\
                "> \n"\
                "> - Add 2015 holiday definitions\n"\
                "</details>\n"\
                "#{commits_details}"\
                "<br />"
              )
          end
        end
      end

      context "switching from a SHA-1 version to a release" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            previous_version: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
            package_manager: "bundler",
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

        before do
          stub_request(
            :get,
            "https://api.github.com/repos/gocardless/business/compare/"\
            "2468a02a6230e59ed1232d95d1ad3ef157195b03...v1.5.0"
          ).with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "business_compare_commits.json"),
              headers: { "Content-Type" => "application/json" }
            )
        end

        it "has the right text" do
          commits_details = commits_details(
            base: "2468a02a6230e59ed1232d95d1ad3ef157195b03",
            head: "v1.5.0"
          )
          expect(pr_message).
            to eq(
              "Bumps [business](https://github.com/gocardless/business) "\
              "from `2468a02` to 1.5.0. This release includes the previously "\
              "tagged commit.\n"\
              "<details>\n"\
              "<summary>Changelog</summary>\n\n"\
              "*Sourced from [business's changelog](https://github.com/"\
              "gocardless/business/blob/master/CHANGELOG.md).*\n\n"\
              "> ## 1.5.0 - June 2, 2015\n"\
              "> \n"\
              "> - Add 2016 holiday definitions\n"\
              "> \n"\
              "> ## 1.4.0 - December 24, 2014\n"\
              "> \n"\
              "> - Add support for custom calendar load paths\n"\
              "> - Remove the 'sepa' calendar\n"\
              "> \n"\
              "> \n"\
              "> ## 1.3.0 - December 2, 2014\n"\
              "> \n"\
              "> - Add `Calendar#previous_business_day`\n"\
              "> \n"\
              "> \n"\
              "> ## 1.2.0 - November 15, 2014\n"\
              "> \n"\
              "> - Add TARGET calendar\n"\
              "> \n"\
              "> \n"\
              "> ## 1.1.0 - September 30, 2014\n"\
              "> \n"\
              "> - Add 2015 holiday definitions\n"\
              "> \n"\
              "> \n"\
              "> ## 1.0.0 - June 11, 2014\n"\
              "> \n"\
              "> - Initial public release\n"\
              "</details>\n"\
              "#{commits_details}"\
              "<br />"
            )
        end
      end

      context "with commits (but no changelog)" do
        before do
          stub_request(:get, "#{business_repo_url}/contents/").
            to_return(
              status: 200,
              body: fixture("github", "business_files_no_changelog.json"),
              headers: json_header
            )
          stub_request(
            :get,
            "https://api.github.com/repos/gocardless/business/compare/"\
            "v1.4.0...v1.5.0"
          ).with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "business_compare_commits.json"),
              headers: { "Content-Type" => "application/json" }
            )
        end

        it "has the right text" do
          expect(pr_message).
            to eq(
              "Bumps [business](https://github.com/gocardless/business) from "\
              "1.4.0 to 1.5.0.\n"\
              "#{commits_details(base: 'v1.4.0', head: 'v1.5.0')}"\
              "<br />"
            )
        end

        context "and release notes text that can be pulled in" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "business",
              version: "1.6.0",
              previous_version: "1.5.0",
              package_manager: "bundler",
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
            stub_request(
              :get,
              "https://api.github.com/repos/gocardless/business/compare/"\
              "v1.5.0...v1.6.0"
            ).with(headers: { "Authorization" => "token token" }).
              to_return(
                status: 200,
                body: fixture("github", "business_compare_commits.json"),
                headers: { "Content-Type" => "application/json" }
              )
          end

          it "has the right text" do
            expect(pr_message).
              to eq(
                "Bumps [business](https://github.com/gocardless/business) "\
                "from 1.5.0 to 1.6.0.\n"\
                "<details>\n"\
                "<summary>Release notes</summary>\n"\
                "\n"\
                "*Sourced from [business's releases](https://github.com/"\
                "gocardless/business/releases).*\n\n"\
                "> ## v1.6.0\n"\
                "> Mad props to [**greysteil**](https://github.com/greysteil) "\
                "for the @angular/scope work\n"\
                "</details>\n"\
                "#{commits_details(base: 'v1.5.0', head: 'v1.6.0')}"\
                "<br />"
              )
          end
        end
      end

      context "and security vulnerabilities fixed" do
        let(:vulnerabilities_fixed) do
          {
            "business" => [{
              "title" => "Serious vulnerability",
              "description" => "A vulnerability that allows arbitrary code\n"\
                               "execution.\n",
              "patched_versions" => ["> 1.5.0"],
              "unaffected_versions" => [],
              "url" => "https://dependabot.com"
            }]
          }
        end

        it "has the right text" do
          expect(pr_message).
            to start_with(
              "Bumps [business](https://github.com/gocardless/business) "\
              "from 1.4.0 to 1.5.0. **This update includes security fixes.**\n"\
              "<details>\n"\
              "<summary>Vulnerabilities fixed</summary>\n\n"\
              "> **Serious vulnerability**\n"\
              "> A vulnerability that allows arbitrary code\n"\
              "> execution.\n"\
              "> \n"\
              "> Patched versions: > 1.5.0\n"\
              "> Unaffected versions: none\n"\
              "\n"\
              "</details>\n"
            )
        end
      end

      context "and an upgrade guide that can be pulled in" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            version: "1.5.0",
            previous_version: "0.9.0",
            package_manager: "bundler",
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
            "https://api.github.com/repos/gocardless/business/compare/"\
            "v0.9.0...v1.5.0"
          ).with(headers: { "Authorization" => "token token" }).
            to_return(
              status: 200,
              body: fixture("github", "business_compare_commits.json"),
              headers: { "Content-Type" => "application/json" }
            )
          stub_request(:get, "#{business_repo_url}/contents/").
            to_return(
              status: 200,
              body:
                fixture("github", "business_files_with_upgrade_guide.json"),
              headers: json_header
            )
          stub_request(:get, "https://api.github.com/repos/gocardless/"\
                         "business/contents/UPGRADE.md").
            to_return(
              status: 200,
              body: fixture("github", "upgrade_guide_contents.json"),
              headers: json_header
            )
        end

        it "has the right text" do
          expect(pr_message).
            to start_with(
              "Bumps [business](https://github.com/gocardless/business) "\
              "from 0.9.0 to 1.5.0.\n"\
              "<details>\n"\
              "<summary>Changelog</summary>\n\n"\
              "*Sourced from [business's changelog](https://github.com/"\
              "gocardless/business/blob/master/CHANGELOG.md).*\n\n"\
              "> ## 1.5.0 - June 2, 2015\n"\
              "> \n"\
              "> - Add 2016 holiday definitions\n"\
              "> \n"\
              "> ## 1.4.0 - December 24, 2014\n"\
              "> \n"\
              "> - Add support for custom calendar load paths\n"\
              "> - Remove the 'sepa' calendar\n"\
              "> \n"\
              "> \n"\
              "> ## 1.3.0 - December 2, 2014\n"\
              "> \n"\
              "> - Add `Calendar#previous_business_day`\n"\
              "> \n"\
              "> \n"\
              "> ## 1.2.0 - November 15, 2014\n"\
              "> \n"\
              "> - Add TARGET calendar\n"\
              "> \n"\
              "> \n"\
              "> ## 1.1.0 - September 30, 2014\n"\
              "> \n"\
              "> - Add 2015 holiday definitions\n"\
              "> \n"\
              "> \n"\
              "> ## 1.0.0 - June 11, 2014\n"\
              "> \n"\
              "> - Initial public release\n"\
              "</details>\n"\
              "<details>\n"\
              "<summary>Upgrade guide</summary>\n\n"\
              "*Sourced from [business's upgrade guide](https://github.com/"\
              "gocardless/business/blob/master/UPGRADE.md).*\n\n"\
              "> UPGRADE GUIDE FROM 2.x to 3.0\n"
            )
        end
      end

      context "updating multiple dependencies" do
        let(:dependencies) { [dependency, dependency2] }
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "statesman",
            version: "1.7.0",
            previous_version: "1.6.0",
            package_manager: "bundler",
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
          stub_request(:get, statesman_repo_url).
            to_return(status: 200,
                      body: fixture("github", "statesman_repo.json"),
                      headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/contents/").
            to_return(status: 200,
                      body: fixture("github", "statesman_files.json"),
                      headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/tags?per_page=100").
            to_return(status: 200,
                      body: fixture("github", "business_tags.json"),
                      headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/releases?per_page=100").
            to_return(status: 200,
                      body: fixture("github", "business_releases.json"),
                      headers: json_header)
          stub_request(:get, "https://api.github.com/repos/gocardless/"\
                             "statesman/contents/CHANGELOG.md").
            to_return(status: 200,
                      body: fixture("github", "changelog_contents.json"),
                      headers: json_header)
          stub_request(:get, "https://rubygems.org/api/v1/gems/statesman.json").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems_response_statesman.json")
            )
        end

        it "includes details of both dependencies" do
          expect(pr_message).
            to eq(
              "Bumps [business](https://github.com/gocardless/business) "\
              "and [statesman](https://github.com/gocardless/statesman). "\
              "These dependencies needed to be updated together.\n\n"\
              "Updates `business` from 1.4.0 to 1.5.0\n"\
              "<details>\n"\
              "<summary>Changelog</summary>\n\n"\
              "*Sourced from [business's changelog](https://github.com/"\
              "gocardless/business/blob/master/CHANGELOG.md).*\n\n"\
              "> ## 1.5.0 - June 2, 2015\n"\
              "> \n"\
              "> - Add 2016 holiday definitions\n"\
              "</details>\n"\
              "#{commits_details(base: 'v1.4.0', head: 'v1.5.0')}"\
              "<br />\n\n"\
              "Updates `statesman` from 1.6.0 to 1.7.0\n"\
              "<details>\n"\
              "<summary>Changelog</summary>\n\n"\
              "*Sourced from [statesman's changelog](https://github.com/"\
              "gocardless/statesman/blob/master/CHANGELOG.md).*\n\n"\
              "> ## 1.7.0 - January 18, 2017\n"\
              "> \n"\
              "> - Add 2018-2027 BACS holiday defintions\n"\
              "</details>\n"\
              "<details>\n"\
              "<summary>Commits</summary>\n\n"\
              "- See full diff in [compare view](https://github.com/gocardless"\
              "/statesman/commits)\n"\
              "</details>\n"\
              "<br />"
            )
        end

        context "for Maven" do
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
          let(:dependency2) do
            Dependabot::Dependency.new(
              name: "org.springframework:spring-context",
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

          let(:spring_beans_maven_url) do
            "https://repo.maven.apache.org/maven2/org/springframework/"\
            "spring-beans/4.3.15.RELEASE/spring-beans-4.3.15.RELEASE.pom"
          end
          let(:spring_context_maven_url) do
            "https://repo.maven.apache.org/maven2/org/springframework/"\
            "spring-context/4.3.15.RELEASE/spring-context-4.3.15.RELEASE.pom"
          end
          let(:guava_parent_maven_url) do
            "https://repo.maven.apache.org/maven2/com/google/guava/"\
            "guava-parent/23.3-jre/guava-parent-23.3-jre.pom"
          end
          let(:maven_response) { fixture("java", "poms", "guava-23.3-jre.xml") }
          let(:pom) do
            Dependabot::DependencyFile.new(
              name: "pom.xml",
              content: fixture("java", "poms", "property_pom.xml")
            )
          end
          let(:files) { [pom] }

          before do
            stub_request(:get, spring_beans_maven_url).
              to_return(status: 200, body: maven_response)
            stub_request(:get, spring_context_maven_url).
              to_return(status: 200, body: maven_response)
            stub_request(:get, guava_parent_maven_url).
              to_return(status: 200, body: maven_response)
          end

          it "has the right intro" do
            expect(pr_message).
              to start_with(
                "Bumps `springframework.version` "\
                "from 4.3.12.RELEASE to 4.3.15.RELEASE.\n\n"
              )
          end
        end
      end
    end

    context "for a library" do
      let(:files) { [gemfile, gemfile_lock, gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          name: "bump.gemspec",
          content: fixture("ruby", "gemspecs", "example")
        )
      end

      it "has the right text" do
        expect(pr_message).
          to eq(
            "Updates the requirements on "\
            "[business](https://github.com/gocardless/business) "\
            "to permit the latest version.\n"\
            "<details>\n"\
            "<summary>Changelog</summary>\n\n"\
            "*Sourced from [business's changelog](https://github.com/"\
            "gocardless/business/blob/master/CHANGELOG.md).*\n\n"\
            "> ## 1.5.0 - June 2, 2015\n"\
            "> \n"\
            "> - Add 2016 holiday definitions\n"\
            "</details>\n"\
            "#{commits_details(base: 'v1.4.0', head: 'v1.5.0')}"\
            "<br />"
          )
      end

      context "updating multiple dependencies" do
        let(:dependencies) { [dependency, dependency2] }
        let(:dependency2) do
          Dependabot::Dependency.new(
            name: "statesman",
            version: "1.7.0",
            previous_version: "1.6.0",
            package_manager: "bundler",
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
          stub_request(:get, statesman_repo_url).
            to_return(status: 200,
                      body: fixture("github", "statesman_repo.json"),
                      headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/contents/").
            to_return(status: 200,
                      body: fixture("github", "statesman_files.json"),
                      headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/tags?per_page=100").
            to_return(status: 200,
                      body: fixture("github", "business_tags.json"),
                      headers: json_header)
          stub_request(:get, "#{statesman_repo_url}/releases?per_page=100").
            to_return(status: 200,
                      body: fixture("github", "business_releases.json"),
                      headers: json_header)
          stub_request(:get, "https://api.github.com/repos/gocardless/"\
                             "statesman/contents/CHANGELOG.md").
            to_return(status: 200,
                      body: fixture("github", "changelog_contents.json"),
                      headers: json_header)
          stub_request(:get, "https://rubygems.org/api/v1/gems/statesman.json").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems_response_statesman.json")
            )
        end

        it "includes details of both dependencies" do
          expect(pr_message).
            to eq(
              "Updates the requirements on "\
              "[business](https://github.com/gocardless/business) "\
              "and [statesman](https://github.com/gocardless/statesman) "\
              "to permit the latest version.\n\n"\
              "Updates `business` from 1.4.0 to 1.5.0\n"\
              "<details>\n"\
              "<summary>Changelog</summary>\n\n"\
              "*Sourced from [business's changelog](https://github.com/"\
              "gocardless/business/blob/master/CHANGELOG.md).*\n\n"\
              "> ## 1.5.0 - June 2, 2015\n"\
              "> \n"\
              "> - Add 2016 holiday definitions\n"\
              "</details>\n"\
              "#{commits_details(base: 'v1.4.0', head: 'v1.5.0')}"\
              "<br />\n\n"\
              "Updates `statesman` from 1.6.0 to 1.7.0\n"\
              "<details>\n"\
              "<summary>Changelog</summary>\n\n"\
              "*Sourced from [statesman's changelog](https://github.com/"\
              "gocardless/statesman/blob/master/CHANGELOG.md).*\n\n"\
              "> ## 1.7.0 - January 18, 2017\n"\
              "> \n"\
              "> - Add 2018-2027 BACS holiday defintions\n"\
              "</details>\n"\
              "<details>\n"\
              "<summary>Commits</summary>\n\n"\
              "- See full diff in [compare view](https://github.com/gocardless"\
              "/statesman/commits)\n"\
              "</details>\n"\
              "<br />"
            )
        end
      end
    end

    context "with a footer" do
      let(:pr_message_footer) { "I'm a footer!" }

      it { is_expected.to end_with("\n\nI'm a footer!") }
    end

    context "with author details" do
      let(:author_details) do
        {
          email: "support@dependabot.com",
          name: "dependabot"
        }
      end

      it "doesn't include a signoff line" do
        expect(pr_message).to_not include("Signed-off-by")
      end
    end
  end

  describe "#commit_message" do
    subject(:commit_message) { builder.commit_message }

    before do
      allow(builder).to receive(:pr_name).and_return("PR name")
      allow(builder).to receive(:commit_message_intro).and_return("Message")
      allow(builder).to receive(:metadata_links).and_return("\n\nLinks")
    end

    it { is_expected.to eq("PR name\n\nMessage\n\nLinks") }

    context "with author details" do
      let(:author_details) do
        {
          email: "support@dependabot.com",
          name: "dependabot"
        }
      end

      it "includes a signoff line" do
        expect(commit_message).
          to end_with("\n\nSigned-off-by: dependabot <support@dependabot.com>")
      end
    end

    context "for a repo that uses gitmoji commits" do
      before do
        allow(builder).to receive(:pr_name).and_call_original
        stub_request(:get, watched_repo_url + "/commits").
          to_return(status: 200,
                    body: fixture("github", "commits_gitmoji.json"),
                    headers: json_header)
      end

      it { is_expected.to start_with(":arrow_up: Bump ") }

      context "with a security vulnerability fixed" do
        let(:vulnerabilities_fixed) { { "business": [{}] } }
        it { is_expected.to start_with(":arrow_up: :lock: Bump ") }
      end
    end
  end
end
