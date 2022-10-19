# frozen_string_literal: true

require "spec_helper"
require "dependabot/source"

RSpec.describe Dependabot::Source do
  describe ".new" do
    subject { described_class.new(**attrs) }

    context "without a hostname or api_endpoint" do
      let(:attrs) { { provider: "github", repo: "my/repo" } }
      its(:url) { is_expected.to eq("https://github.com/my/repo") }
    end

    context "with a hostname and an api_endpoint" do
      let(:attrs) do
        {
          provider: "github",
          repo: "my/repo",
          api_endpoint: "https://my.private.instance/api/v3/",
          hostname: "my.private.instance"
        }
      end

      specify { expect { subject }.to_not raise_error }
    end

    context "with a hostname but no api_endpoint" do
      let(:attrs) do
        {
          provider: "github",
          repo: "my/repo",
          hostname: "my.private.instance"
        }
      end

      specify { expect { subject }.to raise_error(/hostname and api_endpoint/) }
    end

    context "with an api_endpoint but no hostname" do
      let(:attrs) do
        {
          provider: "github",
          repo: "my/repo",
          api_endpoint: "https://my.private.instance/api/v3/"
        }
      end

      specify { expect { subject }.to raise_error(/hostname and api_endpoint/) }
    end
  end

  describe ".from_url" do
    subject { described_class.from_url(url) }

    context "with a GitHub URL" do
      let(:url) { "https://github.com/org/abc" }
      its(:provider) { is_expected.to eq("github") }
      its(:repo) { is_expected.to eq("org/abc") }
      its(:directory) { is_expected.to be_nil }
      its(:branch) { is_expected.to be_nil }

      context "with a git protocol" do
        let(:url) { "git@github.com:org/abc" }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to be_nil }
      end

      context "with a trailing .git" do
        let(:url) { "https://github.com/org/abc.git" }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to be_nil }
      end

      context "with a trailing ." do
        let(:url) { "https://github.com/org/abc. " }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to be_nil }
      end

      context "with a trailing space" do
        let(:url) { "https://github.com/org/abc " }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to be_nil }
      end

      context "with a trailing /" do
        let(:url) { "https://github.com/org/abc/" }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to be_nil }
      end

      context "with a trailing quote" do
        let(:url) { "<a href=\"https://github.com/org/abc\">" }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to be_nil }
      end

      context "with no directory" do
        let(:url) { "https://github.com/org/abc/tree/master/readme.md" }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to be_nil }
      end

      context "with a directory" do
        let(:url) { "https://github.com/org/abc/tree/master/dir/readme.md" }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to eq("dir") }
        its(:branch) { is_expected.to eq("master") }

        context "with the filename specified by a #" do
          let(:url) { "https://github.com/org/abc/tree/master/dir#readme.md" }
          its(:provider) { is_expected.to eq("github") }
          its(:repo) { is_expected.to eq("org/abc") }
          its(:directory) { is_expected.to eq("dir") }
        end

        context "when not looking at the master branch" do
          let(:url) { "https://github.com/org/abc/tree/custom/dir/readme.md" }
          its(:provider) { is_expected.to eq("github") }
          its(:repo) { is_expected.to eq("org/abc") }
          its(:directory) { is_expected.to eq("dir") }
          its(:branch) { is_expected.to eq("custom") }
        end
      end
    end

    context "with a GitHub Enterprise URL" do
      before do
        stub_request(:get, "https://ghes.mycorp.com/status").to_return(
          status: 200,
          body: "GitHub lives!",
          headers: {
            Server: "GitHub.com",
            "X-GitHub-Request-Id": "24e4e058-fdab-5ff4-8d79-be3493b7fa8e"
          }
        )
      end
      let(:url) { "https://ghes.mycorp.com/org/abc" }
      its(:provider) { is_expected.to eq("github") }
      its(:repo) { is_expected.to eq("org/abc") }
      its(:directory) { is_expected.to be_nil }
      its(:branch) { is_expected.to be_nil }

      context "with a git protocol" do
        let(:url) { "ssh://git@ghes.mycorp.com:org/abc" }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to be_nil }
      end

      context "with a trailing .git" do
        let(:url) { "https://ghes.mycorp.com/org/abc.git" }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to be_nil }
      end

      context "with a trailing ." do
        let(:url) { "https://ghes.mycorp.com/org/abc. " }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to be_nil }
      end

      context "with a trailing space" do
        let(:url) { "https://ghes.mycorp.com/org/abc " }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to be_nil }
      end

      context "with a trailing /" do
        let(:url) { "https://ghes.mycorp.com/org/abc/" }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to be_nil }
      end

      context "with a trailing quote" do
        let(:url) { "<a href=\"https://ghes.mycorp.com/org/abc\">" }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to be_nil }
      end

      context "with no directory" do
        let(:url) { "https://ghes.mycorp.com/org/abc/tree/master/readme.md" }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to be_nil }
      end

      context "with a directory" do
        let(:url) { "https://ghes.mycorp.com/org/abc/tree/master/dir/readme.md" }
        its(:provider) { is_expected.to eq("github") }
        its(:repo) { is_expected.to eq("org/abc") }
        its(:directory) { is_expected.to eq("dir") }
        its(:branch) { is_expected.to eq("master") }

        context "with the filename specified by a #" do
          let(:url) { "https://ghes.mycorp.com/org/abc/tree/master/dir#readme.md" }
          its(:provider) { is_expected.to eq("github") }
          its(:repo) { is_expected.to eq("org/abc") }
          its(:directory) { is_expected.to eq("dir") }
        end

        context "when not looking at the master branch" do
          let(:url) { "https://ghes.mycorp.com/org/abc/tree/custom/dir/readme.md" }
          its(:provider) { is_expected.to eq("github") }
          its(:repo) { is_expected.to eq("org/abc") }
          its(:directory) { is_expected.to eq("dir") }
          its(:branch) { is_expected.to eq("custom") }
        end
      end

      context "when the source is not GHES" do
        before do
          stub_request(:get, "https://not-ghes.mycorp.com/status").to_return(
            status: 200,
            body: "This is not GHES!",
            headers: { Server: "nginx" }
          )
        end
        let(:url) { "https://not-ghes.mycorp.com/org/abc" }
        it { is_expected.to be_nil }
      end
    end

    context "with an explicitly ignored URL" do
      let(:url) { "https://gitbox.apache.org/repos/asf?p=commons-lang.git" }
      it { is_expected.to be_nil }
    end

    context "with a Bitbucket URL" do
      let(:url) do
        "https://bitbucket.org/org/abc/src/master/dir/readme.md?at=default"
      end
      its(:provider) { is_expected.to eq("bitbucket") }
      its(:repo) { is_expected.to eq("org/abc") }
      its(:directory) { is_expected.to eq("dir") }
    end

    context "with a GitLab URL" do
      let(:url) { "https://gitlab.com/org/abc/blob/master/dir/readme.md" }
      its(:provider) { is_expected.to eq("gitlab") }
      its(:repo) { is_expected.to eq("org/abc") }
      its(:directory) { is_expected.to eq("dir") }
    end

    context "with a GitLab changelog link" do
      let(:url) { "https://gitlab.com/oauth-xx/oauth2/-/tree/v2.0.9/CHANGELOG.md" }
      its(:provider) { is_expected.to eq("gitlab") }
      its(:repo) { is_expected.to eq("oauth-xx/oauth2") }
      its(:directory) { is_expected.to be_nil }
    end

    context "with a GitLab subgroup URL" do
      let(:url) { "https://gitlab.com/org/group/abc/blob/master/dir/readme.md" }
      its(:provider) { is_expected.to eq("gitlab") }
      its(:repo) { is_expected.to eq("org/group/abc") }
      its(:directory) { is_expected.to eq("dir") }
    end

    context "with an Azure DevOps URL" do
      let(:url) { "https://dev.azure.com/greysteil/_git/dependabot-test?path" }
      its(:provider) { is_expected.to eq("azure") }
      its(:repo) { is_expected.to eq("greysteil/_git/dependabot-test") }
      its(:unscoped_repo) { is_expected.to eq("dependabot-test") }
      its(:organization) { is_expected.to eq("greysteil") }
      its(:project) { is_expected.to eq("dependabot-test") }

      context "that specifies the project" do
        let(:url) do
          "https://dev.azure.com/greysteil/dependabot-test/_git/test2"
        end
        its(:provider) { is_expected.to eq("azure") }
        its(:repo) { is_expected.to eq("greysteil/dependabot-test/_git/test2") }
        its(:unscoped_repo) { is_expected.to eq("test2") }
        its(:organization) { is_expected.to eq("greysteil") }
        its(:project) { is_expected.to eq("dependabot-test") }
      end
    end
  end

  describe "#url_with_directory" do
    let(:source) { described_class.new(**attrs) }
    subject { source.url_with_directory }

    let(:attrs) do
      {
        provider: provider,
        repo: "my/repo",
        directory: directory,
        branch: branch
      }
    end

    let(:provider) { "github" }
    let(:directory) { nil }
    let(:branch) { nil }

    context "without a directory" do
      let(:directory) { nil }
      it { is_expected.to eq("https://github.com/my/repo") }

      context "with a custom hostname" do
        before do
          attrs.merge!(
            hostname: "custom.com",
            api_endpoint: "https://api.custom.com"
          )
        end

        it { is_expected.to eq("https://custom.com/my/repo") }
      end
    end

    context "with a directory" do
      let(:directory) { "lib/a" }
      it { is_expected.to eq("https://github.com/my/repo/tree/HEAD/lib/a") }

      context "that is prefixed with ./" do
        let(:directory) { "./lib/a" }
        it { is_expected.to eq("https://github.com/my/repo/tree/HEAD/lib/a") }
      end

      context "that is prefixed with /" do
        let(:directory) { "/lib/a" }
        it { is_expected.to eq("https://github.com/my/repo/tree/HEAD/lib/a") }
      end

      context "that is the root" do
        let(:directory) { "/" }
        it { is_expected.to eq("https://github.com/my/repo") }
      end
    end
  end
end
