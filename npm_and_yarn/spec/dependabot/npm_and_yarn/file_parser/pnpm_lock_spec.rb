# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser"
require "dependabot/npm_and_yarn/file_parser/pnpm_lock"

RSpec.describe Dependabot::NpmAndYarn::FileParser::PnpmLock do
  subject(:lockfile) { described_class.new(pnpm_lock, dealias_packages: dealias_packages) }

  let(:dealias_packages) { false }
  let(:pnpm_lock) do
    Dependabot::DependencyFile.new(
      name: "pnpm-lock.yaml",
      content: "lockfileVersion: '9.0'\n",
      directory: "/nested"
    )
  end

  context "with helper records" do
    let(:record) do
      {
        "name" => "chalk",
        "version" => "1.0.0",
        "resolved" => "https://registry.example/chalk-1.0.0.tgz",
        "dev" => false,
        "specifiers" => ["^1.0.0"],
        "aliased" => false
      }
    end
    let(:helper_result) { [record] }

    before do
      allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
        .with(
          command: Dependabot::NpmAndYarn::NativeHelpers.helper_path,
          function: "pnpm:parseLockfile",
          args: [kind_of(String)]
        )
        .and_return(helper_result)
    end

    describe "#parsed" do
      subject(:parsed) { lockfile.parsed }

      it "decodes the six helper fields into typed records" do
        expect(parsed).to contain_exactly(
          have_attributes(
            name: "chalk",
            version: "1.0.0",
            resolved: "https://registry.example/chalk-1.0.0.tgz",
            dev: false,
            specifiers: ["^1.0.0"],
            aliased: false
          )
        )
        expect(parsed.first).to be_a(described_class::Record)
      end

      it "memoizes the decoded records" do
        expect(lockfile.parsed).to equal(parsed)
        expect(Dependabot::SharedHelpers).to have_received(:run_helper_subprocess).once
      end

      context "with unknown fields" do
        let(:helper_result) { [record.merge("resolution" => false, "unused" => { "nested" => [nil] })] }

        it "ignores them, including fields used by other lockfile formats" do
          expect(parsed.first).to have_attributes(name: "chalk", version: "1.0.0")
          expect(lockfile.details("chalk", "^1.0.0", nil)).to have_attributes(resolution: nil)
        end
      end

      context "with an omitted resolved URL" do
        let(:helper_result) { [record.except("resolved")] }

        it "retains a nil URL" do
          expect(parsed.first).to have_attributes(resolved: nil)
          expect(lockfile.details("chalk", "^1.0.0", nil)).to have_attributes(resolved: nil)
        end
      end

      context "with empty strings" do
        let(:helper_result) { [record.merge("version" => "", "resolved" => "", "specifiers" => [""])] }

        it "preserves them without changing Dependency version normalization" do
          expect(parsed.first).to have_attributes(version: "", resolved: "", specifiers: [""])
          expect(lockfile.details("chalk", "", nil)).to have_attributes(version: "", resolved: "")
          expect(lockfile.dependencies.dependencies.first).to have_attributes(version: nil)
        end
      end

      context "with duplicate records" do
        let(:helper_result) { [record.merge("version" => "2.0.0", "specifiers" => []), record, record] }

        it "retains the helper's order and duplicates" do
          expect(parsed.map(&:version)).to eq(["2.0.0", "1.0.0", "1.0.0"])
          expect(parsed.map(&:specifiers)).to eq([[], ["^1.0.0"], ["^1.0.0"]])
        end
      end

      context "with an empty helper result" do
        let(:helper_result) { [] }

        it "returns no records, dependencies, or lookup result" do
          expect(parsed).to eq([])
          expect(lockfile.dependencies.dependencies).to eq([])
          expect(lockfile.details("chalk", "^1.0.0", nil)).to be_nil
        end
      end

      [nil, {}, "private helper payload", 123, false].each do |invalid_result|
        context "with #{invalid_result.inspect} instead of an array" do
          let(:helper_result) { invalid_result }

          it "identifies the file and result without including the payload" do
            expect { parsed }
              .to raise_error(Dependabot::DependencyFileNotParseable, "pnpm helper result must be an array") do |error|
                expect(error.file_path).to eq(pnpm_lock.path)
              end
          end
        end
      end

      [nil, [], "private helper payload", 123, false].each do |invalid_record|
        context "with #{invalid_record.inspect} instead of a record" do
          let(:helper_result) { [record, invalid_record] }

          it "identifies the file and record index without including the payload" do
            expect { parsed }
              .to raise_error(
                Dependabot::DependencyFileNotParseable,
                "pnpm helper result[1] must be an object"
              ) do |error|
                expect(error.file_path).to eq(pnpm_lock.path)
              end
          end
        end
      end

      {
        "name" => "a string",
        "version" => "a string",
        "dev" => "a boolean",
        "specifiers" => "an array",
        "aliased" => "a boolean"
      }.each do |field, expected_type|
        context "without #{field}" do
          let(:helper_result) { [record, record.except(field)] }

          it "identifies the missing consumed field" do
            expect { parsed }
              .to raise_error(
                Dependabot::DependencyFileNotParseable,
                "pnpm helper result[1].#{field} must be #{expected_type}"
              ) do |error|
                expect(error.file_path).to eq(pnpm_lock.path)
              end
          end
        end
      end

      [
        ["name", 123, "name", "a string"],
        ["version", false, "version", "a string"],
        ["resolved", nil, "resolved", "a string"],
        ["resolved", { "private" => "payload" }, "resolved", "a string"],
        ["dev", "false", "dev", "a boolean"],
        ["aliased", "false", "aliased", "a boolean"],
        ["specifiers", "^1.0.0", "specifiers", "an array"],
        ["specifiers", ["^1.0.0", nil], "specifiers[1]", "a string"],
        ["specifiers", ["^1.0.0", { "private" => "payload" }], "specifiers[1]", "a string"]
      ].each do |field, invalid_value, context, expected_type|
        context "with invalid #{field}: #{invalid_value.inspect}" do
          let(:helper_result) { [record, record.merge(field => invalid_value)] }

          it "identifies the consumed field without including the payload" do
            expect { parsed }
              .to raise_error(
                Dependabot::DependencyFileNotParseable,
                "pnpm helper result[1].#{context} must be #{expected_type}"
              ) do |error|
                expect(error.file_path).to eq(pnpm_lock.path)
              end
          end
        end
      end

      context "when the helper subprocess fails" do
        before do
          allow(Dependabot::SharedHelpers).to receive(:run_helper_subprocess)
            .and_raise(
              Dependabot::SharedHelpers::HelperSubprocessFailed.new(
                message: "private helper payload",
                error_context: {}
              )
            )
        end

        it "preserves the existing error mapping" do
          expect { parsed }
            .to raise_error(Dependabot::DependencyFileNotParseable, "#{pnpm_lock.path} not parseable") do |error|
              expect(error.file_path).to eq(pnpm_lock.path)
            end
        end
      end
    end

    context "with a malformed aliased record after a valid candidate" do
      let(:helper_result) { [record, record.merge("name" => "hidden", "aliased" => true, "dev" => "private payload")] }

      it "validates records before excluding aliases" do
        expect { lockfile.dependencies }
          .to raise_error(Dependabot::DependencyFileNotParseable, "pnpm helper result[1].dev must be a boolean")
      end

      it "validates every record before selecting a lookup result" do
        expect { lockfile.details("chalk", "^1.0.0", nil) }
          .to raise_error(Dependabot::DependencyFileNotParseable, "pnpm helper result[1].dev must be a boolean")
      end
    end

    describe "#dependencies" do
      subject(:dependency_set) { lockfile.dependencies }

      it "builds dependencies from the record fields" do
        expect(dependency_set.dependencies).to contain_exactly(
          have_attributes(
            name: "chalk",
            version: "1.0.0",
            package_manager: "npm_and_yarn",
            requirements: [],
            metadata: {},
            subdependency_metadata: nil
          )
        )
      end

      context "with development dependencies" do
        let(:helper_result) { [record.merge("dev" => true)] }

        it "preserves development subdependency metadata" do
          expect(dependency_set.dependencies.first).to have_attributes(
            subdependency_metadata: [{ production: false }],
            production?: false
          )
        end
      end

      context "with aliases" do
        let(:helper_result) { [record, record.merge("name" => "aliased-package", "aliased" => true, "dev" => true)] }

        it "excludes aliased packages by default" do
          expect(dependency_set.dependencies.map(&:name)).to eq(["chalk"])
        end

        context "with dealias_packages enabled" do
          let(:dealias_packages) { true }

          it "retains the real name and alias metadata for the grapher" do
            expect(dependency_set.dependencies.map(&:name)).to eq(%w(chalk aliased-package))
            expect(dependency_set.dependency_for_name("aliased-package")).to have_attributes(
              metadata: { alias: "aliased-package" },
              subdependency_metadata: [{ production: false }]
            )
          end
        end
      end

      context "with interleaved specifier-bearing and transitive records" do
        let(:helper_result) do
          [
            record.merge("name" => "transitive-first", "specifiers" => []),
            record.merge("version" => "4.0.0", "specifiers" => []),
            record.merge("name" => "direct-first"),
            record.merge("version" => "3.0.0"),
            record.merge("name" => "transitive-second", "specifiers" => []),
            record.merge("version" => "1.0.0", "specifiers" => []),
            record.merge("name" => "direct-second"),
            record.merge("version" => "2.0.0")
          ]
        end

        it "prioritizes specifier-bearing records with stable ordering in both groups" do
          expect(dependency_set.dependencies.map(&:name))
            .to eq(%w(direct-first chalk direct-second transitive-first transitive-second))
          expect(dependency_set.all_versions_for_name("chalk").map(&:version))
            .to eq(["3.0.0", "2.0.0", "4.0.0", "1.0.0"])
        end

        it "preserves all versions and their order through the aggregate parser" do
          parser = Dependabot::NpmAndYarn::FileParser::LockfileParser.new(dependency_files: [pnpm_lock])
          dependency = parser.parse.find { |dep| dep.name == "chalk" }

          expect(dependency.version).to eq("1.0.0")
          expect(dependency.metadata.fetch(:all_versions).map(&:version))
            .to eq(["3.0.0", "2.0.0", "4.0.0", "1.0.0"])
        end
      end
    end

    describe "#details" do
      subject(:details) { lockfile.details(dependency_name, requirement, nil) }

      let(:dependency_name) { "chalk" }
      let(:requirement) { "^1.0.0" }

      it "returns the common typed lookup result" do
        expect(details).to be_a(Dependabot::Package::NpmLockfileDetails)
        expect(details).to have_attributes(
          version: "1.0.0",
          resolved: "https://registry.example/chalk-1.0.0.tgz",
          resolution: nil
        )
      end

      ["^99.0.0", nil].each do |unmatched_requirement|
        context "with a sole candidate and requirement #{unmatched_requirement.inspect}" do
          let(:requirement) { unmatched_requirement }

          it "uses the sole candidate even though the requirement does not match" do
            expect(details).to have_attributes(version: "1.0.0")
          end
        end
      end

      context "without a matching dependency name" do
        let(:dependency_name) { "missing" }

        it { is_expected.to be_nil }
      end

      context "with an aliased candidate" do
        let(:helper_result) { [record.merge("aliased" => true)] }

        it "keeps lookup behavior independent of alias filtering" do
          expect(details).to have_attributes(version: "1.0.0")
        end
      end

      context "with multiple candidates" do
        let(:helper_result) do
          [
            record.merge("version" => "2.0.0", "specifiers" => ["^2.0.0"]),
            record.merge("specifiers" => ["^1.0.0", ">= 1.0.0 < 2.0.0"]),
            record.merge("version" => "1.1.0")
          ]
        end

        it "uses the first candidate containing the exact specifier" do
          expect(details).to have_attributes(version: "1.0.0")
        end

        context "when a later specifier matches" do
          let(:requirement) { ">= 1.0.0 < 2.0.0" }

          it "preserves the requirement string" do
            expect(details).to have_attributes(version: "1.0.0")
          end
        end

        ["1.0.0", "^1", " >= 1.0.0 < 2.0.0", "^3.0.0", nil].each do |unmatched_requirement|
          context "without exact membership for #{unmatched_requirement.inspect}" do
            let(:requirement) { unmatched_requirement }

            it { is_expected.to be_nil }
          end
        end
      end
    end
  end

  context "with a pnpm 11 multi-document lockfile" do
    let(:pnpm_lock) do
      project_dependency_files("grapher/pnpm_multi_document").find { |file| file.name == "pnpm-lock.yaml" }
    end

    it "decodes only the project records in helper order" do
      expect(lockfile.parsed.map(&:name)).to eq(%w(is-number to-regex-range))
      expect(lockfile.parsed.last).to have_attributes(version: "5.0.1", specifiers: ["5.0.1"], resolved: nil)
    end
  end
end
