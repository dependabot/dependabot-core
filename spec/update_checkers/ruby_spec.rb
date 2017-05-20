# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/update_checkers/ruby"
require_relative "./shared_examples_for_update_checkers"

RSpec.describe Bump::UpdateCheckers::Ruby do
  it_behaves_like "an update checker"

  before do
    stub_request(:get, "https://index.rubygems.org/versions").
      to_return(status: 200, body: fixture("ruby", "rubygems-index"))

    stub_request(:get, "https://index.rubygems.org/api/v1/dependencies").
      to_return(status: 200)

    stub_request(
      :get,
      "https://index.rubygems.org/api/v1/dependencies?gems=business,statesman"
    ).to_return(
      status: 200,
      body: fixture("ruby", "rubygems-dependencies-business-statesman")
    )
  end

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: [gemfile, lockfile],
      github_access_token: "token"
    )
  end

  let(:dependency) do
    Bump::Dependency.new(name: "business", version: "1.3", language: "ruby")
  end

  let(:gemfile) do
    Bump::DependencyFile.new(content: gemfile_body, name: "Gemfile")
  end
  let(:lockfile) do
    Bump::DependencyFile.new(content: lockfile_body, name: "Gemfile.lock")
  end
  let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
  let(:lockfile_body) { fixture("ruby", "lockfiles", "Gemfile.lock") }

  describe "#latest_version" do
    subject { checker.latest_version }

    context "given a gem from rubygems" do
      it { is_expected.to eq(Gem::Version.new("1.8.0")) }

      context "with a version conflict at the latest version" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "version_conflict") }
        let(:lockfile_body) do
          fixture("ruby", "lockfiles", "version_conflict.lock")
        end
        let(:dependency) do
          Bump::Dependency.new(
            name: "ibandit",
            version: "0.1.0",
            language: "ruby"
          )
        end

        before do
          url = "https://index.rubygems.org/api/v1/dependencies?"\
                "gems=i18n,ibandit"
          stub_request(:get, url).
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems-dependencies-i18n-ibandit")
            )

          url = "https://index.rubygems.org/api/v1/dependencies?gems=i18n"
          stub_request(:get, url).
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems-dependencies-i18n")
            )
        end

        # The latest version of ibandit is 0.8.5, but 0.3.4 is the latest
        # version compatible with the version of i18n in the Gemfile.
        it { is_expected.to eq(Gem::Version.new("0.3.4")) }
      end
    end

    context "given a gem from a private gem source" do
      let(:lockfile_body) do
        fixture("ruby", "lockfiles", "specified_source.lock")
      end
      let(:gemfile_body) { fixture("ruby", "gemfiles", "specified_source") }
      let(:gemfury_url) { "https://repo.fury.io/greysteil/" }
      before do
        stub_request(:get, gemfury_url + "versions").
          to_return(status: 200, body: fixture("ruby", "gemfury-index"))

        stub_request(:get, gemfury_url + "api/v1/dependencies").
          to_return(status: 200)

        stub_request(
          :get,
          gemfury_url + "api/v1/dependencies?gems=business,statesman"
        ).to_return(status: 200, body: fixture("ruby", "gemfury_response"))
      end

      it { is_expected.to eq(Gem::Version.new("1.9.0")) }
    end

    context "given a gem with a git source" do
      let(:lockfile_body) { fixture("ruby", "lockfiles", "git_source.lock") }
      let(:gemfile_body) { fixture("ruby", "gemfiles", "git_source") }

      context "that is the gem we're checking" do
        let(:dependency) do
          Bump::Dependency.new(name: "prius", version: "0.9", language: "ruby")
        end

        it { is_expected.to be_nil }
      end

      context "that is not the gem we're checking" do
        it { is_expected.to eq(Gem::Version.new("1.8.0")) }

        context "that is private" do
          let(:gemfile_body) do
            fixture("ruby", "gemfiles", "private_git_source")
          end
          around { |example| capture_stderr { example.run } }

          it "raises a helpful error" do
            expect { checker.latest_version }.
              to raise_error do |error|
                expect(error).to be_a(Bump::GitCommandError)
                expect(error.command).to start_with("git clone 'https://github")
              end
          end
        end
      end
    end

    context "given an unreadable Gemfile" do
      let(:gemfile) do
        Bump::DependencyFile.new(
          content: fixture("ruby", "gemfiles", "includes_requires"),
          name: "Gemfile"
        )
      end

      it "blows up with a useful error" do
        expect { checker.latest_version }.
          to raise_error(Bump::DependencyFileNotEvaluatable)
      end
    end

    context "given a Gemfile that specifies a Ruby version" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "explicit_ruby") }
      it { is_expected.to eq(Gem::Version.new("1.8.0")) }
    end
  end
end
