# frozen_string_literal: true
require "spec_helper"
require "bump/dependency"
require "bump/dependency_file"
require "bump/dependency_file_updaters/ruby/bundler"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Bump::DependencyFileUpdaters::Ruby::Bundler do
  it_behaves_like "a dependency file updater"

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

  let(:updater) do
    described_class.new(
      dependency_files: [gemfile, lockfile],
      dependency: dependency,
      github_access_token: "token"
    )
  end
  let(:gemfile) do
    Bump::DependencyFile.new(content: gemfile_body, name: "Gemfile")
  end
  let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
  let(:lockfile) do
    Bump::DependencyFile.new(content: lockfile_body, name: "Gemfile.lock")
  end
  let(:lockfile_body) { fixture("ruby", "lockfiles", "Gemfile.lock") }
  let(:dependency) do
    Bump::Dependency.new(
      name: "business",
      version: "1.5.0",
      package_manager: "bundler"
    )
  end
  let(:tmp_path) { Bump::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Bump::DependencyFile) }
    end

    its(:length) { is_expected.to eq(2) }

    describe "the updated gemfile" do
      subject(:updated_gemfile) do
        updated_files.find { |f| f.name == "Gemfile" }
      end

      context "when the full version is specified" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "version_specified") }
        its(:content) { is_expected.to include "\"business\", \"~> 1.5.0\"" }
        its(:content) { is_expected.to include "\"statesman\", \"~> 1.2.0\"" }
      end

      context "when the minor version is specified" do
        let(:gemfile_body) do
          fixture("ruby", "gemfiles", "minor_version_specified")
        end
        its(:content) { is_expected.to include "\"business\", \"~> 1.5\"" }
        its(:content) { is_expected.to include "\"statesman\", \"~> 1.2\"" }
      end

      context "with a gem whose name includes a number" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "gem_with_number") }
        let(:lockfile_body) do
          fixture("ruby", "lockfiles", "gem_with_number.lock")
        end
        let(:dependency) do
          Bump::Dependency.new(
            name: "i18n",
            version: "0.5.0",
            package_manager: "bundler"
          )
        end
        before do
          url = "https://index.rubygems.org/api/v1/dependencies?gems=i18n"
          stub_request(:get, url).
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems-dependencies-i18n")
            )
        end
        its(:content) { is_expected.to include "\"i18n\", \"~> 0.5.0\"" }
      end

      context "when there is a comment" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "comments") }
        its(:content) do
          is_expected.to include "\"business\", \"~> 1.5.0\"   # Business time"
        end
      end
    end

    describe "the updated lockfile" do
      subject(:file) { updated_files.find { |f| f.name == "Gemfile.lock" } }

      context "when the old Gemfile specified the version" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "version_specified") }

        it "locks the updated gem to the latest version" do
          expect(file.content).to include "business (1.5.0)"
        end

        it "doesn't change the version of the other (also outdated) gem" do
          expect(file.content).to include "statesman (1.2.1)"
        end

        it "preserves the BUNDLED WITH line in the lockfile" do
          expect(file.content).to include "BUNDLED WITH\n   1.10.6"
        end

        it "doesn't add in a RUBY VERSION" do
          expect(file.content).to_not include "RUBY VERSION"
        end
      end

      context "when the Gemfile specifies a Ruby version" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "explicit_ruby") }
        let(:lockfile_body) do
          fixture("ruby", "lockfiles", "explicit_ruby.lock")
        end

        it "locks the updated gem to the latest version" do
          expect(file.content).to include "business (1.5.0)"
        end

        it "preserves the Ruby version in the lockfile" do
          expect(file.content).to include "RUBY VERSION\n   ruby 2.2.0p0"
        end
      end

      context "when the Gemfile.lock didn't have a BUNDLED WITH line" do
        let(:lockfile_body) do
          fixture("ruby", "lockfiles", "no_bundled_with.lock")
        end

        it "doesn't add in a BUNDLED WITH" do
          expect(file.content).to_not include "BUNDLED WITH"
        end
      end

      context "when the old Gemfile didn't specify the version" do
        let(:gemfile_body) do
          fixture("ruby", "gemfiles", "version_not_specified")
        end

        it "locks the updated gem to the latest version" do
          expect(file.content).to include "business (1.8.0)"
        end

        it "doesn't change the version of the other (also outdated) gem" do
          expect(file.content).to include "statesman (1.2.1)"
        end
      end

      context "when the Gem can't be found" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "unavailable_gem") }

        it "raises a Bump::SharedHelpers::ChildProcessFailed error" do
          expect { updater.updated_dependency_files }.
            to raise_error(Bump::SharedHelpers::ChildProcessFailed)
        end
      end

      context "when another gem in the Gemfile has a git source" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "git_source") }

        it "updates the gem just fine" do
          expect(file.content).to include "business (1.5.0)"
        end

        context "that is private and therefore unreachable" do
          before do
            # Stub the Bundler git clone call to fail. Speeds up specs
            allow_any_instance_of(::Bundler::Source::Git::GitProxy).
              to receive(:`).
              with(%r{^git clone 'https://github\.com/fundingcircle/prius'}).
              and_return(`(exit 128)`)
          end
          let(:gemfile_body) do
            fixture("ruby", "gemfiles", "private_git_source")
          end

          it "raises a helpful error" do
            expect { updater.updated_dependency_files }.
              to raise_error do |error|
                expect(error).to be_a(Bump::GitCommandError)
                expect(error.command).to start_with("git clone 'https://github")
              end
          end
        end
      end

      context "when there is a version conflict" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "version_conflict") }
        let(:lockfile_body) do
          fixture("ruby", "lockfiles", "version_conflict.lock")
        end
        let(:dependency) do
          Bump::Dependency.new(
            name: "ibandit",
            version: "0.8.5",
            package_manager: "bundler"
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

        it "raises a Bump::VersionConflict error" do
          expect { updater.updated_dependency_files }.
            to raise_error(Bump::VersionConflict)
        end
      end
    end
  end
end
