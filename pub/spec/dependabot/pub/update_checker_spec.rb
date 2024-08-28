# typed: false
# frozen_string_literal: true

require "spec_helper"
require "webrick"

require "dependabot/dependency_file"
require "dependabot/dependency"
require "dependabot/pub/update_checker"
require "dependabot/requirements_update_strategy"

require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Pub::UpdateChecker do
  let(:updated_dependencies) do
    checker.updated_dependencies(requirements_to_unlock: requirements_to_unlock).map(&:to_h)
  end
  let(:can_update) { checker.can_update?(requirements_to_unlock: requirements_to_unlock) }
  let(:directory) { nil }
  let(:project) { "can_update" }
  let(:dev_null) { WEBrick::Log.new("/dev/null", 7) }
  let(:server) { WEBrick::HTTPServer.new({ Port: 0, AccessLog: [], Logger: dev_null }) }
  let(:dependency_files) do
    files = project_dependency_files(project)
    files.each do |file|
      # Simulate that the lockfile was from localhost:
      file.content.gsub!("https://pub.dartlang.org", "http://localhost:#{server[:Port]}")
      if defined?(git_dir)
        file.content.gsub!("$GIT_DIR", git_dir)
        file.content.gsub!("$REF", dependency_version)
      end
    end
    files
  end
  let(:requirements) { [] }
  let(:dependency_name) { "lints" }
  let(:requirements_update_strategy) { nil } # nil means "auto".
  let(:dependency_version) { "0.0.0" }
  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      # This version is ignored by dependency_services, but will be seen by base
      version: dependency_version,
      requirements: requirements,
      package_manager: "pub"
    )
  end
  let(:security_advisories) { [] }
  let(:raise_on_ignored) { false }
  let(:ignored_versions) { [] }
  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [{
        "type" => "hosted",
        "host" => "pub.dartlang.org",
        "username" => "x-access-token",
        "password" => "token"
      }],
      ignored_versions: ignored_versions,
      options: {
        pub_hosted_url: "http://localhost:#{server[:Port]}",
        flutter_releases_url: "http://localhost:#{server[:Port]}/flutter_releases.json"
      },
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories,
      requirements_update_strategy: requirements_update_strategy
    )
  end
  let(:sample) { "simple" }
  let(:sample_files) { Dir.glob(File.join("spec", "fixtures", "pub_dev_responses", sample, "*")) }

  after do
    sample_files.each do |f|
      package = File.basename(f, ".json")
      server.unmount "/api/packages/#{package}"
    end
    server.shutdown
  end

  before do
    # Because we do the networking in dependency_services we have to run an
    # actual web server.
    Thread.new do
      server.start
    end
    sample_files.each do |f|
      package = File.basename(f, ".json")
      server.mount_proc "/api/packages/#{package}" do |_req, res|
        res.body = File.read(File.join("..", "..", "..", f))
      end
    end
    server.mount_proc "/flutter_releases.json" do |_req, res|
      res.body = File.read(File.join(__dir__, "..", "..", "fixtures", "flutter_releases.json"))
    end
  end

  it_behaves_like "an update checker"

  context "when given an outdated dependency, not requiring unlock" do
    let(:dependency_name) { "collection" }

    context "when unlocking all" do
      let(:requirements_to_unlock) { :all }

      it "can update" do
        expect(can_update).to be_truthy
        expect(updated_dependencies).to eq [
          { "name" => "collection",
            "package_manager" => "pub",
            "previous_requirements" => [{
              file: "pubspec.yaml", groups: ["direct"], requirement: "^1.15.0", source: nil
            }],
            "previous_version" => "1.15.0",
            "requirements" => [{
              file: "pubspec.yaml", groups: ["direct"], requirement: "^1.19.0", source: nil
            }],
            "version" => "1.19.0" }
        ]
      end
    end

    context "when unlocking own" do
      let(:requirements_to_unlock) { :own }

      context "with auto-strategy" do
        context "when dealing with an app (no version)" do
          it "can update" do
            expect(can_update).to be_truthy
            expect(updated_dependencies).to eq [
              { "name" => "collection",
                "package_manager" => "pub",
                "previous_requirements" => [],
                # Dependabot lifts this from the original dependency.
                "previous_version" => "0.0.0",
                "requirements" => [{
                  file: "pubspec.yaml", groups: ["direct"], requirement: "^1.19.0", source: nil
                }],
                "version" => "1.19.0" }
            ]
          end
        end

        context "when dealing with a library (has version)" do
          let(:project) { "can_update_library" }

          it "can update" do
            expect(can_update).to be_truthy
            expect(updated_dependencies).to eq [
              { "name" => "collection",
                "package_manager" => "pub",
                "previous_requirements" => [],
                # Dependabot lifts this from the original dependency.
                "previous_version" => "0.0.0",
                "requirements" => [{
                  file: "pubspec.yaml", groups: ["direct"], requirement: "^1.15.0", source: nil
                }],
                "version" => "1.19.0" }
            ]
          end
        end
      end

      context "with bump_versions strategy" do
        let(:requirements_update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }

        it "can update" do
          expect(can_update).to be_truthy
          expect(updated_dependencies).to eq [
            { "name" => "collection",
              "package_manager" => "pub",
              "previous_requirements" => [],
              # Dependabot lifts this from the original dependency.
              "previous_version" => "0.0.0",
              "requirements" => [{
                file: "pubspec.yaml", groups: ["direct"], requirement: "^1.19.0", source: nil
              }],
              "version" => "1.19.0" }
          ]
        end
      end

      context "with bump_versions_if_necessary strategy" do
        let(:requirements_update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary }

        it "can update" do
          expect(can_update).to be_truthy
          expect(updated_dependencies).to eq [
            { "name" => "collection",
              "package_manager" => "pub",
              "previous_requirements" => [],
              # Dependabot lifts this from the original dependency.
              "previous_version" => "0.0.0",
              "requirements" => [{
                file: "pubspec.yaml", groups: ["direct"], requirement: "^1.15.0", source: nil
              }],
              "version" => "1.19.0" }
          ]
        end
      end

      context "with widen_ranges strategy" do
        let(:requirements_update_strategy) { Dependabot::RequirementsUpdateStrategy::WidenRanges }

        it "can update" do
          expect(can_update).to be_truthy
          expect(updated_dependencies).to eq [
            { "name" => "collection",
              "package_manager" => "pub",
              "previous_requirements" => [],
              # Dependabot lifts this from the original dependency.
              "previous_version" => "0.0.0",
              "requirements" => [{
                # No widening needed for this update.
                file: "pubspec.yaml", groups: ["direct"], requirement: "^1.15.0", source: nil
              }],
              "version" => "1.19.0" }
          ]
        end
      end
    end

    context "when unlocking none" do
      let(:requirements_to_unlock) { :none }

      it "can update" do
        expect(can_update).to be_truthy
        expect(updated_dependencies).to eq [
          { "name" => "collection",
            "package_manager" => "pub",
            "previous_requirements" => [],
            # Dependabot lifts this from the original dependency.
            "previous_version" => "0.0.0",
            "requirements" => [],
            "version" => "1.19.0" }
        ]
      end
    end

    context "when not upgrading to ignored version" do
      let(:requirements_to_unlock) { :none }
      let(:ignored_versions) { ["1.19.0"] }

      it "cannot update" do
        expect(can_update).to be_falsey
      end
    end
  end

  context "when given an outdated dependency, requiring unlock" do
    let(:dependency_name) { "lints" }

    context "when unlocking all" do
      let(:requirements_to_unlock) { :all }

      context "with auto-strategy" do
        context "when dealing with an app (no version)" do
          it "can update" do
            expect(can_update).to be_truthy
            expect(updated_dependencies).to eq [
              { "name" => "lints",
                "package_manager" => "pub",
                "previous_requirements" => [{
                  file: "pubspec.yaml", groups: ["dev"], requirement: "^3.0.0", source: nil
                }],
                "previous_version" => "3.0.0",
                "requirements" => [{
                  file: "pubspec.yaml", groups: ["dev"], requirement: "^4.0.0", source: nil
                }],
                "version" => "4.0.0" }
            ]
          end
        end

        context "when dealing with an app (version but publish_to: none)" do
          let(:project) { "can_update_publish_to_none" }

          it "can update" do
            expect(can_update).to be_truthy
            expect(updated_dependencies).to eq [
              { "name" => "lints",
                "package_manager" => "pub",
                "previous_requirements" => [{
                  file: "pubspec.yaml", groups: ["dev"], requirement: "^3.0.0", source: nil
                }],
                "previous_version" => "3.0.0",
                "requirements" => [{
                  file: "pubspec.yaml", groups: ["dev"], requirement: "^4.0.0", source: nil
                }],
                "version" => "4.0.0" }
            ]
          end
        end

        context "when dealing with a library (has version)" do
          let(:project) { "can_update_library" }

          it "can update" do
            expect(can_update).to be_truthy
            expect(updated_dependencies).to eq [
              { "name" => "lints",
                "package_manager" => "pub",
                "previous_requirements" => [{
                  file: "pubspec.yaml", groups: ["dev"], requirement: "^3.0.0", source: nil
                }],
                "previous_version" => "3.0.0",
                "requirements" => [{
                  file: "pubspec.yaml", groups: ["dev"], requirement: ">=3.0.0 <5.0.0", source: nil
                }],
                "version" => "4.0.0" }
            ]
          end
        end
      end

      context "with bump_versions strategy" do
        let(:requirements_update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersions }

        it "can update" do
          expect(can_update).to be_truthy
          expect(updated_dependencies).to eq [
            { "name" => "lints",
              "package_manager" => "pub",
              "previous_requirements" => [{
                file: "pubspec.yaml", groups: ["dev"], requirement: "^3.0.0", source: nil
              }],
              "previous_version" => "3.0.0",
              "requirements" => [{
                file: "pubspec.yaml", groups: ["dev"], requirement: "^4.0.0", source: nil
              }],
              "version" => "4.0.0" }
          ]
        end
      end

      context "with bump_versions_if_necessary strategy" do
        let(:requirements_update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary }

        it "can update" do
          expect(can_update).to be_truthy
          expect(updated_dependencies).to eq [
            { "name" => "lints",
              "package_manager" => "pub",
              "previous_requirements" => [{
                file: "pubspec.yaml", groups: ["dev"], requirement: "^3.0.0", source: nil
              }],
              "previous_version" => "3.0.0",
              "requirements" => [{
                file: "pubspec.yaml", groups: ["dev"], requirement: "^4.0.0", source: nil
              }],
              "version" => "4.0.0" }
          ]
        end
      end

      context "with widen_ranges strategy" do
        let(:requirements_update_strategy) { Dependabot::RequirementsUpdateStrategy::WidenRanges }

        it "can update" do
          expect(can_update).to be_truthy
          expect(updated_dependencies).to eq [
            { "name" => "lints",
              "package_manager" => "pub",
              "previous_requirements" => [{
                file: "pubspec.yaml", groups: ["dev"], requirement: "^3.0.0", source: nil
              }],
              "previous_version" => "3.0.0",
              "requirements" => [{
                file: "pubspec.yaml", groups: ["dev"], requirement: ">=3.0.0 <5.0.0", source: nil
              }],
              "version" => "4.0.0" }
          ]
        end
      end
    end

    context "when unlocking own" do
      let(:requirements_to_unlock) { :own }

      it "can update" do
        expect(can_update).to be_truthy
        expect(updated_dependencies).to eq [
          { "name" => "lints",
            "package_manager" => "pub",
            "previous_requirements" => [],
            "previous_version" => "0.0.0",
            "requirements" => [{
              file: "pubspec.yaml", groups: ["dev"], requirement: "^4.0.0", source: nil
            }],
            "version" => "4.0.0" }
        ]
      end
    end

    context "when not upgrading to ignored version" do
      let(:requirements_to_unlock) { :own }
      let(:ignored_versions) { ["4.0.0"] }

      it "cannot update" do
        expect(can_update).to be_falsey
        # Ideally we could update to 3.0.0 here. This is currently a limitation
        # of the pub dependency_services.
      end
    end

    context "when unlocking none" do
      let(:requirements_to_unlock) { :none }

      it "can update" do
        expect(can_update).to be_falsey
      end
    end
  end

  context "when given an outdated dependency, requiring full unlock" do
    let(:dependency_name) { "pub_semver" }

    context "when unlocking all" do
      let(:requirements_to_unlock) { :all }

      it "can update" do
        expect(can_update).to be_truthy
        expect(updated_dependencies).to eq [
          {
            "name" => "pub_semver",
            "version" => "2.1.4",
            "requirements" => [{ requirement: "2.1.4", groups: ["direct"], source: nil, file: "pubspec.yaml" }],
            "previous_version" => "2.0.0",
            "previous_requirements" => [{
              requirement: "2.0.0", groups: ["direct"], source: nil, file: "pubspec.yaml"
            }],
            "package_manager" => "pub"
          },
          {
            "name" => "meta",
            "version" => "1.15.0",
            "requirements" => [{ requirement: "1.15.0", groups: ["direct"], source: nil, file: "pubspec.yaml" }],
            "previous_version" => "1.3.0-nullsafety.6",
            "previous_requirements" => [{
              requirement: "1.3.0-nullsafety.6", groups: ["direct"], source: nil, file: "pubspec.yaml"
            }],
            "package_manager" => "pub"
          },
        ]
      end
    end

    context "when in a workspace" do
      let(:dependency_name) { "meta" }
      let(:project) { "can_update_workspace" }
      let(:requirements_to_unlock) { :all }

      it "can update" do
        expect(can_update).to be_truthy
        expect(updated_dependencies).to eq [
          { "name" => "meta",
            "package_manager" => "pub",
            "previous_requirements" => [{
              file: "pubspec.yaml",
              groups: ["direct"],
              requirement: "1.6.0",
              source: nil
            }],
            "previous_version" => "1.6.0",
            "requirements" => [{
              file: "pubspec.yaml", groups: ["direct"], requirement: "1.15.0", source: nil
            }],
            "version" => "1.15.0" }
        ]
      end
    end

    context "when unlocking own" do
      let(:requirements_to_unlock) { :own }

      it "can update" do
        expect(can_update).to be_falsey
      end
    end

    context "when unlocking none" do
      let(:requirements_to_unlock) { :none }

      it "can update" do
        expect(can_update).to be_falsey
      end
    end
  end

  context "when given an up-to-date dependency" do
    let(:dependency_name) { "path" }

    context "when unlocking all" do
      let(:requirements_to_unlock) { :all }

      it "can update" do
        expect(can_update).to be_falsey
      end
    end

    context "when unlocking own" do
      let(:requirements_to_unlock) { :own }

      it "can update" do
        expect(can_update).to be_falsey
      end
    end

    context "when unlocking none" do
      let(:requirements_to_unlock) { :none }

      it "can update" do
        expect(can_update).to be_falsey
      end
    end
  end

  describe "#lowest_resolvable_security_fix_version" do
    subject(:lowest_resolvable_security_fix_version) { checker.lowest_resolvable_security_fix_version }

    let(:dependency_name) { "lints" }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "pub",
          vulnerable_versions: ["<4.0.0"]
        )
      ]
    end

    before do
      # Allow network. We use it to install flutter.
      WebMock.allow_net_connect!
      # To find the vulnerable versions we do a package listing before invoking the helper.
      # Stub this out here:
      stub_request(:get, "http://localhost:#{server[:Port]}/api/packages/#{dependency.name}").to_return(
        status: 200,
        body: fixture("pub_dev_responses/simple/#{dependency.name}.json"),
        headers: {}
      )
    end

    context "when a newer non-vulnerable version is available" do
      it "updates to the lowest non-vulnerable version" do
        expect(lowest_resolvable_security_fix_version).to eq(Gem::Version.new("4.0.0"))
      end
    end

    context "when transitive deps can be unlocked" do
      let(:requirements_to_unlock) { :all }
      let(:dependency_name) { "pub_semver" }
      let(:dependency_version) { "2.0.0" }
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "pub",
            vulnerable_versions: ["2.0.0"]
          )
        ]
      end

      it "can update" do
        expect(checker).to be_vulnerable
        expect(checker.lowest_resolvable_security_fix_version).to eq("2.1.0")
        expect(updated_dependencies).to eq [
          {
            "name" => "pub_semver",
            "version" => "2.1.0",
            "requirements" => [{ requirement: "2.1.0", groups: ["direct"], source: nil, file: "pubspec.yaml" }],
            "previous_version" => "2.0.0",
            "previous_requirements" => [{
              requirement: "2.0.0", groups: ["direct"], source: nil, file: "pubspec.yaml"
            }],
            "package_manager" => "pub"
          },
          {
            "name" => "meta",
            "version" => "1.3.0",
            "requirements" => [{ requirement: "1.3.0", groups: ["direct"], source: nil, file: "pubspec.yaml" }],
            "previous_version" => "1.3.0-nullsafety.6",
            "previous_requirements" => [{
              requirement: "1.3.0-nullsafety.6", groups: ["direct"], source: nil, file: "pubspec.yaml"
            }],
            "package_manager" => "pub"
          }
        ]
      end
    end

    context "when the current version is not newest but also not vulnerable" do
      let(:dependency_version) { "4.0.0" }

      it "raises an error" do
        expect { lowest_resolvable_security_fix_version }.to raise_error(RuntimeError) do |error|
          expect(error.message).to eq("Dependency not vulnerable!")
        end
      end
    end
  end

  describe "#lowest_security_fix_version" do
    subject(:lowest_security_fix_version) { checker.lowest_security_fix_version }

    before do
      # Allow network. We use it to install flutter.
      WebMock.allow_net_connect!
      # To find the vulnerable versions we do a package listing before invoking the helper.
      # Stub this out here:
      stub_request(:get, "http://localhost:#{server[:Port]}/api/packages/#{dependency.name}").to_return(
        status: 200,
        body: fixture("pub_dev_responses/simple/#{dependency.name}.json"),
        headers: {}
      )
    end

    let(:dependency_name) { "lints" }
    let(:dependency_version) { "3.0.0" }

    # TODO: Implement https://github.com/dependabot/dependabot-core/issues/5391, then flip "highest" to "lowest"
    it "keeps current version if it is not vulnerable" do
      expect(lowest_security_fix_version).to eq(Gem::Version.new("3.0.0"))
    end

    context "with a security vulnerability on older versions" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "pub",
            vulnerable_versions: ["< 4.0.0"]
          )
        ]
      end

      it "finds the lowest available non-vulnerable version" do
        expect(lowest_security_fix_version).to eq(Gem::Version.new("4.0.0"))
      end

      # it "returns nil for git versions" # tested elsewhere under `context "With a git dependency"`
    end

    context "with a security vulnerability on all newer versions" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "pub",
            vulnerable_versions: ["< 5.0.0"]
          )
        ]
      end

      it { is_expected.to be_nil }
    end
  end

  context "when dealing with mono repo" do
    let(:project) { "mono_repo_main_at_root" }
    let(:dependency_name) { "dep" }

    context "when unlocking none" do
      let(:requirements_to_unlock) { :none }

      it "can update" do
        expect(checker.latest_version.to_s).to eq "1.0.0"
        expect(can_update).to be_falsey
      end
    end
  end

  context "when raise_on_ignored is true" do
    let(:raise_on_ignored) { true }

    context "when later versions are allowed" do
      let(:dependency_name) { "collection" }
      let(:dependency_version) { "1.14.13" }
      let(:ignored_versions) { ["< 1.14.13"] }

      it "doesn't raise an error" do
        expect { checker.latest_version }.not_to raise_error
      end
    end

    context "when the user is on the latest version" do
      let(:dependency_name) { "path" }
      let(:dependency_version) { "1.9.0" }
      let(:ignored_versions) { ["> 1.9.0"] }

      it "doesn't raise an error" do
        expect { checker.latest_version }.not_to raise_error
      end
    end

    context "when the user is on the latest version but it's ignored" do
      let(:dependency_name) { "path" }
      let(:dependency_version) { "1.9.0" }
      let(:ignored_versions) { [">= 0"] }

      it "doesn't raise an error" do
        expect { checker.latest_version }.not_to raise_error
      end
    end

    context "when the user is ignoring all later versions" do
      let(:dependency_name) { "collection" }
      let(:dependency_version) { "1.14.13" }
      let(:ignored_versions) { ["> 1.14.13"] }
      let(:raise_on_ignored) { true }

      it "raises an error" do
        expect { checker.latest_version }.to raise_error(Dependabot::AllVersionsIgnored)
      end
    end
  end

  context "with a git dependency" do
    include_context "with temp dir"

    let(:project) { "git_dependency" }

    let(:git_dir) { File.join(temp_dir, "foo.git") }
    let(:foo_pubspec) { File.join(git_dir, "pubspec.yaml") }

    let(:dependency_name) { "foo" }
    let(:requirements) do
      [{
        file: "pubspec.yaml",
        requirement: "~3.0.0",
        groups: [],
        source: {
          "type" => "git",
          "description" => {
            "url" => git_dir,
            "path" => "foo",
            "ref" => "1adc00411d4e1184d248d0147de3348a287f2fea"
          }
        }
      }]
    end
    let(:dependency_version) do
      FileUtils.mkdir_p git_dir
      run_git ["init"], git_dir

      File.write(foo_pubspec, '{"name":"foo", "version": "1.0.0", "environment": {"sdk": "^2.0.0"}}')
      run_git ["add", "."], git_dir
      run_git ["commit", "-am", "some commit message"], git_dir
      ref = run_git(%w(rev-parse HEAD), git_dir).strip
      ref
    end
    let(:requirements_to_unlock) { :all }
    let(:requirements_update_strategy) { Dependabot::RequirementsUpdateStrategy::BumpVersionsIfNecessary }

    it "updates to latest git commit" do
      dependency_version # triggers the initial commit.
      File.write(foo_pubspec, '{"name":"foo", "version": "2.0.0", "environment": {"sdk": "^2.0.0"}}')
      run_git ["add", "."], git_dir
      run_git ["commit", "-am", "some commit message"], git_dir
      new_ref = run_git(%w(rev-parse HEAD), git_dir).strip
      expect(can_update).to be_truthy
      expect(updated_dependencies).to eq [
        { "name" => "foo",
          "package_manager" => "pub",
          "previous_requirements" => [{
            file: "pubspec.yaml", groups: ["direct"], requirement: "any", source: nil
          }],
          "previous_version" => dependency_version,
          "requirements" => [{
            file: "pubspec.yaml", groups: ["direct"], requirement: "any", source: nil
          }],
          "version" => new_ref }
      ]
    end

    context "with a security vulnerability on older versions" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "pub",
            vulnerable_versions: ["< 3.0.0"]
          )
        ]
      end

      it "returns no version" do
        expect(checker.lowest_security_fix_version).to be_nil
      end
    end
  end

  context "when working for a flutter project" do
    include_context "with temp dir"

    let(:project) { "requires_flutter" }
    let(:requirements_to_unlock) { :all }
    let(:dependency_name) { "lints" }

    it "can update" do
      expect(can_update).to be_truthy
      expect(updated_dependencies).to eq [
        { "name" => "lints",
          "package_manager" => "pub",
          "previous_requirements" => [{
            file: "pubspec.yaml", groups: ["dev"], requirement: "^3.0.0", source: nil
          }],
          "previous_version" => "3.0.0",
          "requirements" => [{
            file: "pubspec.yaml", groups: ["dev"], requirement: "^4.0.0", source: nil
          }],
          "version" => "4.0.0" }
      ]
    end
  end

  context "when working for a flutter project requiring a flutter beta" do
    include_context "with temp dir"

    let(:project) { "requires_latest_beta" }
    let(:requirements_to_unlock) { :all }
    let(:dependency_name) { "lints" }

    it "can update" do
      expect(can_update).to be_truthy
      expect(updated_dependencies).to eq [
        { "name" => "lints",
          "package_manager" => "pub",
          "previous_requirements" => [{
            file: "pubspec.yaml", groups: ["dev"], requirement: "^3.0.0", source: nil
          }],
          "previous_version" => "3.0.0",
          "requirements" => [{
            file: "pubspec.yaml", groups: ["dev"], requirement: "^4.0.0", source: nil
          }],
          "version" => "4.0.0" }
      ]
    end
  end

  context "when loading a YAML file with alias" do
    fixture = "spec/fixtures/projects/yaml_alias/"
    alias_info_file = "pubspec_alias_true.yaml"
    non_alias_info_file = "pubspec.yaml"
    it "parses a alias contained YAML file with aliases: true" do
      yaml_object = File.open(fixture + alias_info_file, "r")
      data = yaml_object.read
      expect { YAML.safe_load(data, aliases: true) }.not_to raise_error
    end

    it "parses a alias contained YAML file with aliases: false" do
      yaml_object = File.open(fixture + alias_info_file, "r")
      data = yaml_object.read
      expect { YAML.safe_load(data, aliases: false) }.to raise_error(Psych::AliasesNotEnabled)
    end

    it "parses a no alias YAML file with aliases: true" do
      yaml_object = File.open(fixture + non_alias_info_file, "r")
      data = yaml_object.read
      expect { YAML.safe_load(data, aliases: true) }.not_to raise_error
    end
  end
end
