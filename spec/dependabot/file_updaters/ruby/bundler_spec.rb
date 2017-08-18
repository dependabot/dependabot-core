# frozen_string_literal: true
require "spec_helper"
require "bundler/compact_index_client"
require "bundler/compact_index_client/updater"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/file_updaters/ruby/bundler"
require_relative "../shared_examples_for_file_updaters"

RSpec.describe Dependabot::FileUpdaters::Ruby::Bundler do
  it_behaves_like "a dependency file updater"

  before do
    allow_any_instance_of(Bundler::CompactIndexClient::Updater).
      to receive(:etag_for).
      and_return("")
  end

  before do
    stub_request(:get, "https://index.rubygems.org/versions").
      to_return(status: 200, body: fixture("ruby", "rubygems-index"))

    stub_request(:get, "https://index.rubygems.org/info/business").
      to_return(
        status: 200,
        body: fixture("ruby", "rubygems-info-business")
      )

    stub_request(:get, "https://index.rubygems.org/info/statesman").
      to_return(
        status: 200,
        body: fixture("ruby", "rubygems-info-statesman")
      )
  end

  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      dependency: dependency,
      github_access_token: "token"
    )
  end
  let(:dependency_files) { [gemfile, lockfile] }
  let(:gemfile) do
    Dependabot::DependencyFile.new(content: gemfile_body, name: "Gemfile")
  end
  let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
  let(:lockfile) do
    Dependabot::DependencyFile.new(content: lockfile_body, name: "Gemfile.lock")
  end
  let(:lockfile_body) { fixture("ruby", "lockfiles", "Gemfile.lock") }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.5.0",
      requirement: "~> 1.5.0",
      package_manager: "bundler",
      groups: []
    )
  end
  let(:tmp_path) { Dependabot::SharedHelpers::BUMP_TMP_DIR_PATH }

  before { Dir.mkdir(tmp_path) unless Dir.exist?(tmp_path) }

  describe "#updated_dependency_files" do
    subject(:updated_files) { updater.updated_dependency_files }

    it "doesn't store the files permanently" do
      expect { updated_files }.to_not(change { Dir.entries(tmp_path) })
    end

    it "returns DependencyFile objects" do
      updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
    end

    its(:length) { is_expected.to eq(2) }

    describe "the updated gemfile" do
      subject(:updated_gemfile) do
        updated_files.find { |f| f.name == "Gemfile" }
      end

      context "when no change is required" do
        let(:gemfile_body) do
          fixture("ruby", "gemfiles", "version_not_specified")
        end
        it { is_expected.to be_nil }
      end

      context "when the full version is specified" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "version_specified") }
        its(:content) { is_expected.to include "\"business\", \"~> 1.5.0\"" }
        its(:content) { is_expected.to include "\"statesman\", \"~> 1.2.0\"" }
      end

      context "when a pre-release is specified" do
        let(:gemfile_body) do
          fixture("ruby", "gemfiles", "prerelease_specified")
        end
        its(:content) { is_expected.to include "\"business\", \"~> 1.5.0\"" }
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
          Dependabot::Dependency.new(
            name: "i18n",
            version: "0.5.0",
            requirement: "~> 0.5.0",
            package_manager: "bundler",
            groups: []
          )
        end
        before do
          stub_request(:get, "https://index.rubygems.org/info/i18n").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems-info-i18n")
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

      context "with a greater than or equal to matcher" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "gte_matcher") }
        its(:content) { is_expected.to include "\"business\", \">= 1.5.0\"" }
      end

      context "with a less than matcher" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "less_than_matcher") }
        its(:content) { is_expected.to include "\"business\", \"~> 1.5.0\"" }
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

        context "but the lockfile didn't include that version" do
          let(:lockfile_body) { fixture("ruby", "lockfiles", "Gemfile.lock") }

          it "doesn't add in a RUBY VERSION" do
            expect(file.content).to_not include "RUBY VERSION"
          end
        end

        context "that is legacy" do
          let(:gemfile_body) { fixture("ruby", "gemfiles", "legacy_ruby") }
          let(:lockfile_body) do
            fixture("ruby", "lockfiles", "legacy_ruby.lock")
          end
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "public_suffix",
              version: "1.4.6",
              requirement: "~> 1.4.0",
              package_manager: "bundler",
              groups: []
            )
          end

          before do
            stub_request(:get, "https://index.rubygems.org/info/public_suffix").
              to_return(
                status: 200,
                body: fixture("ruby", "rubygems-info-public_suffix")
              )
          end

          it "locks the updated gem to the latest version" do
            expect(file.content).to include "public_suffix (1.4.6)"
          end

          it "preserves the Ruby version in the lockfile" do
            expect(file.content).to include "RUBY VERSION\n   ruby 1.9.3p551"
          end
        end
      end

      context "given a Gemfile that loads a .ruby-version file" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "ruby_version_file") }
        let(:ruby_version_file) do
          Dependabot::DependencyFile.new(content: "2.2", name: ".ruby-version")
        end
        let(:updater) do
          described_class.new(
            dependency_files: [gemfile, lockfile, ruby_version_file],
            dependency: dependency,
            github_access_token: "token"
          )
        end

        it "locks the updated gem to the latest version" do
          expect(file.content).to include "business (1.5.0)"
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

      context "when another gem in the Gemfile has a git source" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "git_source") }
        let(:lockfile_body) { fixture("ruby", "lockfiles", "git_source.lock") }

        it "updates the gem just fine" do
          expect(file.content).to include "business (1.5.0)"
        end

        it "doesn't update the git dependencies" do
          old_lock = lockfile_body.split(/^/)
          new_lock = file.content.split(/^/)

          %w(prius que uk_phone_numbers).each do |dep|
            original_remote_line =
              old_lock.find { |l| l.include?("gocardless/#{dep}") }
            original_revision_line =
              old_lock[old_lock.find_index(original_remote_line) + 1]

            new_remote_line =
              new_lock.find { |l| l.include?("gocardless/#{dep}") }
            new_revision_line =
              new_lock[new_lock.find_index(original_remote_line) + 1]

            expect(new_remote_line).to eq(original_remote_line)
            expect(new_revision_line).to eq(original_revision_line)
            expect(new_lock.index(new_remote_line)).
              to eq(old_lock.index(original_remote_line))
          end
        end
      end

      context "when another gem in the Gemfile has a path source" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "path_source") }
        let(:lockfile_body) { fixture("ruby", "lockfiles", "path_source.lock") }

        context "that we've downloaded" do
          let(:gemspec_body) { fixture("ruby", "gemspecs", "example") }
          let(:gemspec) do
            Dependabot::DependencyFile.new(
              content: gemspec_body,
              name: "plugins/example/example.gemspec"
            )
          end

          let(:dependency_files) { [gemfile, lockfile, gemspec] }

          before do
            stub_request(:get, "https://index.rubygems.org/info/i18n").
              to_return(
                status: 200,
                body: fixture("ruby", "rubygems-info-i18n")
              )
            stub_request(:get, "https://index.rubygems.org/info/public_suffix").
              to_return(
                status: 200,
                body: fixture("ruby", "rubygems-info-public_suffix")
              )
          end

          it "updates the gem just fine" do
            expect(file.content).to include "business (1.5.0)"
          end

          context "that requires other files" do
            let(:gemspec_body) { fixture("ruby", "gemspecs", "with_require") }

            it "updates the gem just fine" do
              expect(file.content).to include "business (1.5.0)"
            end

            it "doesn't change the version of the path dependency" do
              expect(file.content).to include "example (0.9.3)"
            end
          end
        end
      end

      context "with a Gemfile that imports a gemspec" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "imports_gemspec") }
        let(:gemspec_body) { fixture("ruby", "gemspecs", "small_example") }
        let(:lockfile_body) do
          fixture("ruby", "lockfiles", "imports_gemspec.lock")
        end
        let(:gemspec) do
          Dependabot::DependencyFile.new(
            content: gemspec_body,
            name: "example.gemspec"
          )
        end

        let(:dependency_files) { [gemfile, lockfile, gemspec] }

        context "when the gem in the gemspec isn't being updated" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "statesman",
              version: "2.0.0",
              requirement: ">= 1.0, < 3.0",
              package_manager: "bundler",
              groups: []
            )
          end

          it "returns an updated Gemfile and Gemfile.lock" do
            expect(updated_files.map(&:name)).
              to match_array(["Gemfile", "Gemfile.lock"])
          end
        end

        context "when the gem in the gemspec is being updated" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "business",
              version: "1.8.0",
              requirement: requirement,
              package_manager: "bundler",
              groups: []
            )
          end
          let(:requirement) { ">= 1.0, < 3.0" }

          it "returns an updated gemspec, Gemfile and Gemfile.lock" do
            expect(updated_files.map(&:name)).
              to match_array(["Gemfile", "Gemfile.lock", "example.gemspec"])
          end

          context "but the gemspec constraint is already satisfied" do
            let(:requirement) { "~> 1.0" }

            it "returns an updated Gemfile and Gemfile.lock" do
              expect(updated_files.map(&:name)).
                to match_array(["Gemfile", "Gemfile.lock"])
            end
          end

          context "and only appears in the gemspec" do
            let(:gemspec_body) { fixture("ruby", "gemspecs", "no_overlap") }
            let(:lockfile_body) do
              fixture("ruby", "lockfiles", "imports_gemspec_no_overlap.lock")
            end
            let(:dependency) do
              Dependabot::Dependency.new(
                name: "json",
                version: "2.0.3",
                requirement: ">= 1.0, < 3.0",
                package_manager: "bundler",
                groups: []
              )
            end

            before do
              stub_request(:get, "https://index.rubygems.org/info/json").
                to_return(
                  status: 200,
                  body: fixture("ruby", "rubygems-info-json")
                )
            end

            it "returns an updated gemspec and Gemfile.lock" do
              expect(updated_files.map(&:name)).
                to match_array(["example.gemspec", "Gemfile.lock"])
            end
          end
        end
      end
    end

    context "when provided with only a gemspec" do
      let(:dependency_files) { [gemspec] }

      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: gemspec_body,
          name: "example.gemspec"
        )
      end
      let(:gemspec_body) { fixture("ruby", "gemspecs", "example") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "5.1.0",
          requirement: ">= 4.6, < 6.0",
          package_manager: "bundler",
          groups: []
        )
      end
      let(:dependency_name) { "octokit" }

      it "returns DependencyFile objects" do
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
      end

      its(:length) { is_expected.to eq(1) }

      describe "the updated gemspec" do
        subject(:updated_gemspec) { updated_files.first }

        context "when no change is required" do
          let(:dependency_name) { "rake" }
          it { is_expected.to be_nil }
        end

        its(:content) do
          is_expected.to include(%("octokit", ">= 4.6", "< 6.0"\n))
        end

        context "with a runtime dependency" do
          let(:dependency_name) { "bundler" }

          its(:content) do
            is_expected.to include(%("bundler", ">= 4.6", "< 6.0"\n))
          end
        end

        context "with a development dependency" do
          let(:dependency_name) { "webmock" }

          its(:content) do
            is_expected.to include(%("webmock", ">= 4.6", "< 6.0"\n))
          end
        end

        context "with an array of requirements" do
          let(:dependency_name) { "excon" }

          its(:content) do
            is_expected.to include(%("excon", ">= 4.6", "< 6.0"\n))
          end
        end

        context "with brackets around the requirements" do
          let(:dependency_name) { "gemnasium-parser" }

          its(:content) do
            is_expected.to include(%("gemnasium-parser", ">= 4.6", "< 6.0"\n))
          end
        end

        context "with single quotes" do
          let(:dependency_name) { "gems" }

          its(:content) do
            is_expected.to include(%('gems', '>= 4.6', '< 6.0'\n))
          end
        end
      end
    end

    context "when provided with a Gemfile and a gemspec" do
      let(:dependency_files) { [gemfile, gemspec] }

      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: gemspec_body,
          name: "example.gemspec"
        )
      end
      let(:gemspec_body) { fixture("ruby", "gemspecs", "example") }
      let(:gemfile_body) { fixture("ruby", "gemfiles", "imports_gemspec") }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "5.1.0",
          requirement: ">= 4.6, < 6.0",
          package_manager: "bundler",
          groups: []
        )
      end
      let(:dependency_name) { "octokit" }

      it "returns an updated gemspec DependencyFile objects" do
        updated_files.each { |f| expect(f).to be_a(Dependabot::DependencyFile) }
        expect(updated_files.count).to eq(1)
        expect(updated_files.first.name).to eq("example.gemspec")
      end

      context "when the gem appears in both" do
        let(:gemspec_body) { fixture("ruby", "gemspecs", "small_example") }
        let(:dependency_name) { "business" }

        its(:length) { is_expected.to eq(2) }

        describe "the updated gemspec" do
          subject(:updated_gemspec) do
            updated_files.find { |f| f.name == "example.gemspec" }
          end

          its(:content) do
            is_expected.to include(%('business', '>= 4.6', '< 6.0'\n))
          end
        end

        describe "the updated gemfile" do
          subject(:updated_gemspec) do
            updated_files.find { |f| f.name == "Gemfile" }
          end

          its(:content) { is_expected.to include(%("business", "~> 5.1.0"\n)) }
        end
      end
    end

    context "when provided with only a Gemfile" do
      let(:dependency_files) { [gemfile] }

      # TODO: It would be nice to support this case. Work needed is in
      # PullRequestCreator
      it "raises on initialization" do
        expect { updater }.to raise_error(/Gemfile and Gemfile\.lock/)
      end
    end

    context "when provided with only a Gemfile.lock" do
      let(:dependency_files) { [lockfile] }

      it "raises on initialization" do
        expect { updater }.to raise_error(/Gemfile must be provided/)
      end
    end

    context "when provided with only a gemspec and Gemfile.lock" do
      let(:dependency_files) { [lockfile, gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: fixture("ruby", "gemspecs", "example"),
          name: "example.gemspec"
        )
      end

      it "raises on initialization" do
        expect { updater }.to raise_error(/Gemfile must be provided/)
      end
    end
  end
end
