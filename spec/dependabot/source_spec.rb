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
          api_endpoint: "https://my.private.insance/api/v3/",
          hostname: "my.private.insance"
        }
      end

      specify { expect { subject }.to_not raise_error }
    end

    context "with a hostname but no api_endpoint" do
      let(:attrs) do
        {
          provider: "github",
          repo: "my/repo",
          hostname: "my.private.insance"
        }
      end

      specify { expect { subject }.to raise_error(/hostname and api_endpoint/) }
    end

    context "with an api_endpoint but no hostname" do
      let(:attrs) do
        {
          provider: "github",
          repo: "my/repo",
          api_endpoint: "https://my.private.insance/api/v3/"
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

        context "with the filename specified by a #" do
          let(:url) { "https://github.com/org/abc/tree/master/dir#readme.md" }
          its(:provider) { is_expected.to eq("github") }
          its(:repo) { is_expected.to eq("org/abc") }
          its(:directory) { is_expected.to eq("dir") }
        end
      end
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
  end
end
