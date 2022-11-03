# frozen_string_literal: true

require "json"
require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/nuget/file_updater/lockfile_updater"

RSpec.describe Dependabot::Nuget::FileUpdater::LockfileUpdater do
  let(:updater) do
    described_class.new(
      dependency_files: dependency_files,
      lock_file: lockfile,
      credentials: [{
        "type" => "git_source",
        "host" => "github.com"
      }]
    )
  end

  let(:dependency_files) { [csproj, lockfile] }
  let(:csproj) do
    Dependabot::DependencyFile.new(name: "myproj.csproj", content: csproj_body)
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(name: "packages.lock.json", content: lockfile_body)
  end
  let(:csproj_body) { fixture("csproj", csproj_fixture_name) }
  let(:lockfile_body) { fixture("lockfiles", lockfile_fixture_name) }
  let(:csproj_fixture_name) { "lockfiles_basic" }
  let(:lockfile_fixture_name) { "lockfiles_basic" }
  let(:tmp_path) { Dependabot::Utils::BUMP_TMP_DIR_PATH }

  before { FileUtils.mkdir_p(tmp_path) }

  describe "#updated_lockfile_content" do
    subject(:updated_lockfile_content) { updater.updated_lockfile_content }

    it "doesn't store the files permanently" do
      expect { updated_lockfile_content }.
        to_not(change { Dir.entries(tmp_path) })
    end

    it { expect { updated_lockfile_content }.to_not output.to_stdout }

    context "when updating the lockfile fails" do
      let(:csproj_body) { fixture("csproj", csproj_fixture_name).gsub('Version="0.11.1"', 'Version="99.99.99"') }

      it "raises a helpful error" do
        expect { updater.updated_lockfile_content }.
          to raise_error do |error|
            expect(error).
              to be_a(Dependabot::SharedHelpers::HelperSubprocessFailed)
            expect(error.message).to include(
              "Failed to restore /home/dependabot/dependabot-core/nuget/dependabot_tmp_dir/myproj.csproj"
            )
            expect(error.message).to include(
              "error NU1102: Unable to find package Azure.Bicep.Core with version (>= 99.99.99)"
            )
          end
      end
    end

    describe "the updated lockfile" do
      it "updates the dependency version in the lockfile" do
        prev_dependency = JSON.parse(lockfile_body)["dependencies"]["net6.0"]["Azure.Bicep.Core"]
        new_dependency = JSON.parse(updated_lockfile_content)["dependencies"]["net6.0"]["Azure.Bicep.Core"]

        expect(prev_dependency["resolved"]).to eql("0.7.4")
        expect(prev_dependency["contentHash"]).to eql(
          "G9FJNOcZBc74IQe7Uars6SVM8Kvum/ZJp0eyZ8Q47fiEn5+aBTFf36NkRKkknzT2bXkGubmwNa1copSiDAdzVg=="
        )

        expect(new_dependency["resolved"]).to eql("0.11.1")
        expect(new_dependency["contentHash"]).to eql(
          "S6NZBEy/D9UhN45XAiL8ZnUfzMLC/jTklcyd7/xizMhQYzMutcj6D9Dzseu2Svd4lgUFSelDHR7O62bn88niVw=="
        )
      end
    end
  end
end
