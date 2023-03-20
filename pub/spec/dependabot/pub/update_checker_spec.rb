# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/pub/update_checker"
require "webrick"

require_common_spec "update_checkers/shared_examples_for_update_checkers"

RSpec.describe Dependabot::Pub::UpdateChecker do
  it_behaves_like "an update checker"

  before(:all) do
    # Because we do the networking in dependency_services we have to run an
    # actual web server.
    dev_null = WEBrick::Log.new("/dev/null", 7)
    @server = WEBrick::HTTPServer.new({ Port: 0, AccessLog: [], Logger: dev_null })
    Thread.new do
      @server.start
    end
  end

  after(:all) do
    @server.shutdown
  end

  before do
    sample_files.each do |f|
      package = File.basename(f, ".json")
      @server.mount_proc "/api/packages/#{package}" do |_req, res|
        res.body = File.read(File.join("..", "..", f))
      end
    end
    @server.mount_proc "/flutter_releases.json" do |_req, res|
      res.body = File.read(File.join(__dir__, "..", "..", "fixtures", "flutter_releases.json"))
    end
  end

  after do
    sample_files.each do |f|
      package = File.basename(f, ".json")
      @server.unmount "/api/packages/#{package}"
    end
  end

  let(:sample_files) { Dir.glob(File.join("spec", "fixtures", "pub_dev_responses", sample, "*")) }
  let(:sample) { "simple" }

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
        pub_hosted_url: "http://localhost:#{@server[:Port]}",
        flutter_releases_url: "http://localhost:#{@server[:Port]}/flutter_releases.json"
      },
      raise_on_ignored: raise_on_ignored,
      security_advisories: security_advisories,
      requirements_update_strategy: requirements_update_strategy
    )
  end

  let(:ignored_versions) { [] }
  let(:raise_on_ignored) { false }
  let(:security_advisories) { [] }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: dependency_name,
      # This version is ignored by dependency_services, but will be seen by base
      version: dependency_version,
      requirements: requirements,
      package_manager: "pub"
    )
  end
  let(:dependency_version) { "0.0.0" }

  let(:requirements_update_strategy) { nil } # nil means "auto".
  let(:dependency_name) { "retry" }
  let(:requirements) { [] }

  let(:dependency_files) do
    files = project_dependency_files(project)
    files.each do |file|
      # Simulate that the lockfile was from localhost:
      file.content.gsub!("https://pub.dartlang.org", "http://localhost:#{@server[:Port]}")
      if defined?(git_dir)
        file.content.gsub!("$GIT_DIR", git_dir)
        file.content.gsub!("$REF", dependency_version)
      end
    end
    files
  end
  let(:project) { "can_update" }
  let(:directory) { nil }

  let(:can_update) { checker.can_update?(requirements_to_unlock: requirements_to_unlock) }
  let(:updated_dependencies) do
    checker.updated_dependencies(requirements_to_unlock: requirements_to_unlock).map(&:to_h)
  end

  context "given an outdated dependency, not requiring unlock" do
    let(:dependency_name) { "collection" }

    context "unlocking all" do
      let(:requirements_to_unlock) { :all }
      it "can update" do
        expect(can_update).to be_truthy
        expect(updated_dependencies).to eq [
          { "name" => "collection",
            "package_manager" => "pub",
            "previous_requirements" => [{
              file: "pubspec.yaml", groups: ["direct"], requirement: "^1.14.13", source: nil
            }],
            "previous_version" => "1.14.13",
            "requirements" => [{
              file: "pubspec.yaml", groups: ["direct"], requirement: "^1.16.0", source: nil
            }],
            "version" => "1.16.0" }
        ]
      end
    end

    context "unlocking own" do
      let(:requirements_to_unlock) { :own }
      context "with auto-strategy" do
        context "app (no version)" do
          it "can update" do
            expect(can_update).to be_truthy
            expect(updated_dependencies).to eq [
              { "name" => "collection",
                "package_manager" => "pub",
                "previous_requirements" => [],
                # Dependabot lifts this from the original dependency.
                "previous_version" => "0.0.0",
                "requirements" => [{
                  file: "pubspec.yaml", groups: ["direct"], requirement: "^1.16.0", source: nil
                }],
                "version" => "1.16.0" }
            ]
          end
        end
        context "library (has version)" do
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
                  file: "pubspec.yaml", groups: ["direct"], requirement: "^1.14.13", source: nil
                }],
                "version" => "1.16.0" }
            ]
          end
        end
      end
      context "with bump_versions strategy" do
        let(:requirements_update_strategy) { "bump_versions" }
        it "can update" do
          expect(can_update).to be_truthy
          expect(updated_dependencies).to eq [
            { "name" => "collection",
              "package_manager" => "pub",
              "previous_requirements" => [],
              # Dependabot lifts this from the original dependency.
              "previous_version" => "0.0.0",
              "requirements" => [{
                file: "pubspec.yaml", groups: ["direct"], requirement: "^1.16.0", source: nil
              }],
              "version" => "1.16.0" }
          ]
        end
      end
      context "with bump_versions_if_necessary strategy" do
        let(:requirements_update_strategy) { "bump_versions_if_necessary" }
        it "can update" do
          expect(can_update).to be_truthy
          expect(updated_dependencies).to eq [
            { "name" => "collection",
              "package_manager" => "pub",
              "previous_requirements" => [],
              # Dependabot lifts this from the original dependency.
              "previous_version" => "0.0.0",
              "requirements" => [{
                file: "pubspec.yaml", groups: ["direct"], requirement: "^1.14.13", source: nil
              }],
              "version" => "1.16.0" }
          ]
        end
      end
      context "with widen_ranges strategy" do
        let(:requirements_update_strategy) { "widen_ranges" }
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
                file: "pubspec.yaml", groups: ["direct"], requirement: "^1.14.13", source: nil
              }],
              "version" => "1.16.0" }
          ]
        end
      end
    end

    context "unlocking none" do
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
            "version" => "1.16.0" }
        ]
      end
    end

    context "will not upgrade to ignored version" do
      let(:requirements_to_unlock) { :none }
      let(:ignored_versions) { ["1.16.0"] }
      it "cannot update" do
        expect(can_update).to be_falsey
      end
    end
  end

  context "given an outdated dependency, requiring unlock" do
    let(:dependency_name) { "retry" }

    context "unlocking all" do
      let(:requirements_to_unlock) { :all }
      context "with auto-strategy" do
        context "app (no version)" do
          it "can update" do
            expect(can_update).to be_truthy
            expect(updated_dependencies).to eq [
              { "name" => "retry",
                "package_manager" => "pub",
                "previous_requirements" => [{
                  file: "pubspec.yaml", groups: ["direct"], requirement: "^2.0.0", source: nil
                }],
                "previous_version" => "2.0.0",
                "requirements" => [{
                  file: "pubspec.yaml", groups: ["direct"], requirement: "^3.1.0", source: nil
                }],
                "version" => "3.1.0" }
            ]
          end
        end
        context "app (version but publish_to: none)" do
          let(:project) { "can_update_publish_to_none" }
          it "can update" do
            expect(can_update).to be_truthy
            expect(updated_dependencies).to eq [
              { "name" => "retry",
                "package_manager" => "pub",
                "previous_requirements" => [{
                  file: "pubspec.yaml", groups: ["direct"], requirement: "^2.0.0", source: nil
                }],
                "previous_version" => "2.0.0",
                "requirements" => [{
                  file: "pubspec.yaml", groups: ["direct"], requirement: "^3.1.0", source: nil
                }],
                "version" => "3.1.0" }
            ]
          end
        end
        context "library (has version)" do
          let(:project) { "can_update_library" }
          it "can update" do
            expect(can_update).to be_truthy
            expect(updated_dependencies).to eq [
              { "name" => "retry",
                "package_manager" => "pub",
                "previous_requirements" => [{
                  file: "pubspec.yaml", groups: ["direct"], requirement: "^2.0.0", source: nil
                }],
                "previous_version" => "2.0.0",
                "requirements" => [{
                  file: "pubspec.yaml", groups: ["direct"], requirement: ">=2.0.0 <4.0.0", source: nil
                }],
                "version" => "3.1.0" }
            ]
          end
        end
      end
      context "with bump_versions strategy" do
        let(:requirements_update_strategy) { "bump_versions" }
        it "can update" do
          expect(can_update).to be_truthy
          expect(updated_dependencies).to eq [
            { "name" => "retry",
              "package_manager" => "pub",
              "previous_requirements" => [{
                file: "pubspec.yaml", groups: ["direct"], requirement: "^2.0.0", source: nil
              }],
              "previous_version" => "2.0.0",
              "requirements" => [{
                file: "pubspec.yaml", groups: ["direct"], requirement: "^3.1.0", source: nil
              }],
              "version" => "3.1.0" }
          ]
        end
      end
      context "with bump_versions_if_necessary strategy" do
        let(:requirements_update_strategy) { "bump_versions_if_necessary" }
        it "can update" do
          expect(can_update).to be_truthy
          expect(updated_dependencies).to eq [
            { "name" => "retry",
              "package_manager" => "pub",
              "previous_requirements" => [{
                file: "pubspec.yaml", groups: ["direct"], requirement: "^2.0.0", source: nil
              }],
              "previous_version" => "2.0.0",
              "requirements" => [{
                file: "pubspec.yaml", groups: ["direct"], requirement: "^3.1.0", source: nil
              }],
              "version" => "3.1.0" }
          ]
        end
      end
      context "with widen_ranges strategy" do
        let(:requirements_update_strategy) { "widen_ranges" }
        it "can update" do
          expect(can_update).to be_truthy
          expect(updated_dependencies).to eq [
            { "name" => "retry",
              "package_manager" => "pub",
              "previous_requirements" => [{
                file: "pubspec.yaml", groups: ["direct"], requirement: "^2.0.0", source: nil
              }],
              "previous_version" => "2.0.0",
              "requirements" => [{
                file: "pubspec.yaml", groups: ["direct"], requirement: ">=2.0.0 <4.0.0", source: nil
              }],
              "version" => "3.1.0" }
          ]
        end
      end
    end

    context "unlocking own" do
      let(:requirements_to_unlock) { :own }
      it "can update" do
        expect(can_update).to be_truthy
        expect(updated_dependencies).to eq [
          { "name" => "retry",
            "package_manager" => "pub",
            "previous_requirements" => [],
            "previous_version" => "0.0.0",
            "requirements" => [{
              file: "pubspec.yaml", groups: ["direct"], requirement: "^3.1.0", source: nil
            }],
            "version" => "3.1.0" }
        ]
      end
    end

    context "will not upgrade to ignored version" do
      let(:requirements_to_unlock) { :own }
      let(:ignored_versions) { ["3.1.0"] }
      it "cannot update" do
        expect(can_update).to be_falsey
        # Ideally we could update to 3.0.0 here. This is currently a limitation
        # of the pub dependency_services.
      end
    end

    context "unlocking none" do
      let(:requirements_to_unlock) { :none }
      it "can update" do
        expect(can_update).to be_falsey
      end
    end
  end
  context "given an outdated dependency, requiring full unlock" do
    let(:dependency_name) { "protobuf" }

    context "unlocking all" do
      let(:requirements_to_unlock) { :all }
      it "can update" do
        expect(can_update).to be_truthy
        expect(updated_dependencies).to eq [
          {
            "name" => "protobuf",
            "version" => "2.0.0",
            "requirements" => [{ requirement: "^2.0.0", groups: ["direct"], source: nil, file: "pubspec.yaml" }],
            "previous_version" => "1.1.4",
            "previous_requirements" => [{
              requirement: "1.1.4", groups: ["direct"], source: nil, file: "pubspec.yaml"
            }],
            "package_manager" => "pub"
          },
          {
            "name" => "fixnum",
            "version" => "1.0.0",
            "requirements" => [{ requirement: "^1.0.0", groups: ["direct"], source: nil, file: "pubspec.yaml" }],
            "previous_version" => "0.10.11",
            "previous_requirements" => [{
              requirement: "0.10.11", groups: ["direct"], source: nil, file: "pubspec.yaml"
            }],
            "package_manager" => "pub"
          }

        ]
      end
    end

    context "unlocking own" do
      let(:requirements_to_unlock) { :own }
      it "can update" do
        expect(can_update).to be_falsey
      end
    end

    context "unlocking none" do
      let(:requirements_to_unlock) { :none }
      it "can update" do
        expect(can_update).to be_falsey
      end
    end
  end
  context "given an up-to-date dependency" do
    let(:dependency_name) { "path" }

    context "unlocking all" do
      let(:requirements_to_unlock) { :all }
      it "can update" do
        expect(can_update).to be_falsey
      end
    end

    context "unlocking own" do
      let(:requirements_to_unlock) { :own }
      it "can update" do
        expect(can_update).to be_falsey
      end
    end

    context "unlocking none" do
      let(:requirements_to_unlock) { :none }
      it "can update" do
        expect(can_update).to be_falsey
      end
    end
  end

  describe "#lowest_resolvable_security_fix_version" do
    subject(:lowest_resolvable_security_fix_version) { checker.lowest_resolvable_security_fix_version }
    let(:dependency_name) { "retry" }
    let(:security_advisories) do
      [
        Dependabot::SecurityAdvisory.new(
          dependency_name: dependency_name,
          package_manager: "pub",
          vulnerable_versions: ["<3.0.0"]
        )
      ]
    end

    context "when a newer non-vulnerable version is available" do
      # TODO: Implement https://github.com/dependabot/dependabot-core/issues/5391, then flip "highest" to "lowest"
      it "updates to the highest non-vulnerable version" do
        is_expected.to eq(Gem::Version.new("3.1.0"))
      end
    end

    # TODO: should it update indirect deps for security vulnerabilities? I assume Pub has these?
    # examples of how to write tests in go_modules/update_checker_spec

    context "when the current version is not newest but also not vulnerable" do
      let(:dependency_version) { "3.0.0" } # 3.1.0 is latest
      it "raises an error " do
        expect { lowest_resolvable_security_fix_version.to }.to raise_error(RuntimeError) do |error|
          expect(error.message).to eq("Dependency not vulnerable!")
        end
      end
    end
  end

  describe "#lowest_security_fix_version" do
    subject(:lowest_security_fix_version) { checker.lowest_security_fix_version }
    let(:dependency_name) { "retry" }

    # TODO: Implement https://github.com/dependabot/dependabot-core/issues/5391, then flip "highest" to "lowest"
    it "finds the highest available non-vulnerable version" do
      is_expected.to eq(Gem::Version.new("3.1.0"))
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

      # TODO: Implement https://github.com/dependabot/dependabot-core/issues/5391, then flip "highest" to "lowest"
      it "finds the highest available non-vulnerable version" do
        is_expected.to eq(Gem::Version.new("3.1.0"))
      end

      # it "returns nil for git versions" # tested elsewhere under `context "With a git dependency"`
    end

    context "with a security vulnerability on all newer versions" do
      let(:security_advisories) do
        [
          Dependabot::SecurityAdvisory.new(
            dependency_name: dependency_name,
            package_manager: "pub",
            vulnerable_versions: ["< 4.0.0"]
          )
        ]
      end
      it { is_expected.to be_nil }
    end
  end

  context "mono repo" do
    let(:project) { "mono_repo_main_at_root" }
    let(:dependency_name) { "dep" }
    context "unlocking none" do
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
        expect { checker.latest_version }.to_not raise_error
      end
    end

    context "when the user is on the latest version" do
      let(:dependency_name) { "path" }
      let(:dependency_version) { "1.8.0" }
      let(:ignored_versions) { ["> 1.8.0"] }

      it "doesn't raise an error" do
        expect { checker.latest_version }.to_not raise_error
      end
    end

    context "when the user is on the latest version but it's ignored" do
      let(:dependency_name) { "path" }
      let(:dependency_version) { "1.8.0" }
      let(:ignored_versions) { [">= 0"] }

      it "doesn't raise an error" do
        expect { checker.latest_version }.to_not raise_error
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

  context "With a git dependency" do
    include_context :uses_temp_dir

    let(:project) { "git_dependency" }

    let(:git_dir) { File.join(temp_dir, "foo.git") }
    let(:foo_pubspec) { File.join(git_dir, "pubspec.yaml") }

    let(:dependency_name) { "foo" }
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
    let(:requirements_update_strategy) { "bump_versions_if_necessary" }

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

  context "works for a flutter project" do
    include_context :uses_temp_dir

    let(:project) { "requires_flutter" }
    let(:requirements_to_unlock) { :all }
    let(:dependency_name) { "retry" }
    it "can update" do
      expect(can_update).to be_truthy
      expect(updated_dependencies).to eq [
        { "name" => "retry",
          "package_manager" => "pub",
          "previous_requirements" => [{
            file: "pubspec.yaml", groups: ["direct"], requirement: "^2.0.0", source: nil
          }],
          "previous_version" => "2.0.0",
          "requirements" => [{
            file: "pubspec.yaml", groups: ["direct"], requirement: "^3.1.0", source: nil
          }],
          "version" => "3.1.0" }
      ]
    end
  end

  context "works for a flutter project requiring a flutter beta" do
    include_context :uses_temp_dir

    let(:project) { "requires_latest_beta" }
    let(:requirements_to_unlock) { :all }
    let(:dependency_name) { "retry" }
    it "can update" do
      expect(can_update).to be_truthy
      expect(updated_dependencies).to eq [
        { "name" => "retry",
          "package_manager" => "pub",
          "previous_requirements" => [{
            file: "pubspec.yaml", groups: ["direct"], requirement: "^2.0.0", source: nil
          }],
          "previous_version" => "2.0.0",
          "requirements" => [{
            file: "pubspec.yaml", groups: ["direct"], requirement: "^3.1.0", source: nil
          }],
          "version" => "3.1.0" }
      ]
    end
  end
end
