# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/bun/file_updater/package_json_updater"

RSpec.describe Dependabot::Bun::FileUpdater::PackageJsonUpdater do
  extend T::Sig

  describe "#updated_package_json" do
    subject(:updated_content) do
      described_class.new(package_json: package_json, dependencies: [dependency]).updated_package_json.content
    end

    let(:package_json) { Dependabot::DependencyFile.new(name: "package.json", content: content) }
    let(:dependency) do
      Dependabot::Dependency.new(
        name: dependency_name,
        version: "7.0.0",
        previous_version: "6.0.0",
        package_manager: "bun",
        requirements: groups.map { |group| requirement(group, new_requirement) },
        previous_requirements: groups.map { |group| requirement(group, previous_requirement) }
      )
    end
    let(:dependency_name) { "is-number" }
    let(:groups) { ["dependencies"] }
    let(:previous_requirement) { "6.0.0" }
    let(:new_requirement) { "7.0.0" }
    let(:source) { nil }

    sig { params(group: String, requirement: T.nilable(String)).returns(T::Hash[Symbol, T.anything]) }
    def requirement(group, requirement)
      { file: "package.json", requirement: requirement, groups: [group], source: source }
    end

    context "when a compact declaration with the same requirement precedes the section" do
      let(:content) do
        <<~JSON
          {
            "workspaces": {"packages":["packages/*"],"catalog":{"is-number":"6.0.0"}},
            "dependencies": {
              "is-number": "6.0.0"
            }
          }
        JSON
      end

      it "updates the section" do
        expect(updated_content).to eq(content.sub('"is-number": "6.0.0"', '"is-number": "7.0.0"'))
      end
    end

    context "when a nested dependencies object declares the same requirement" do
      let(:content) do
        <<~JSON
          {
            "pnpm": {
              "packageExtensions": {
                "left-pad@1": { "dependencies": { "is-number": "6.0.0" } }
              }
            },
            "dependencies": { "is-number": "6.0.0" }
          }
        JSON
      end

      it "updates only the top-level section" do
        expect(updated_content).to eq(
          content.sub(%("dependencies": { "is-number": "6.0.0" }\n}), %("dependencies": { "is-number": "7.0.0" }\n}))
        )
      end
    end

    context "when a compact nested dependencies object precedes the section" do
      let(:content) do
        <<~JSON
          {
            "pnpm": {"packageExtensions":{"left-pad@1":{"dependencies":{"is-number":"6.0.0"}}}},
            "dependencies": {
              "is-number": "6.0.0"
            }
          }
        JSON
      end

      it "updates only the top-level section" do
        expect(updated_content).to eq(content.sub('"is-number": "6.0.0"', '"is-number": "7.0.0"'))
      end
    end

    context "when the dependency is in two sections and the first declaration is compact" do
      let(:groups) { %w(dependencies devDependencies) }
      let(:content) do
        <<~JSON
          {
            "devDependencies": {"is-number":"6.0.0"},
            "dependencies": {
              "is-number": "6.0.0"
            }
          }
        JSON
      end

      it "updates both sections" do
        expect(updated_content).to eq(
          content.sub('"is-number":"6.0.0"', '"is-number":"7.0.0"').sub('"is-number": "6.0.0"', '"is-number": "7.0.0"')
        )
      end
    end

    context "when the key is written with an escape" do
      let(:content) do
        <<~JSON
          {
            "dependencies": {
              "is-\\u006eumber": "6.0.0"
            }
          }
        JSON
      end

      it "updates the declaration" do
        expect(updated_content).to eq(content.sub('"6.0.0"', '"7.0.0"'))
      end
    end

    context "when a compact git declaration moves to a registry requirement" do
      let(:source) { { type: "git", url: "https://github.com/jonschlinkert/is-number", branch: nil, ref: "6.0.0" } }
      let(:dependency) do
        Dependabot::Dependency.new(
          name: dependency_name,
          version: "7.0.0",
          previous_version: "6.0.0",
          package_manager: "bun",
          requirements: [{ file: "package.json", requirement: "^7.0.0", groups: ["dependencies"], source: nil }],
          previous_requirements: [requirement("dependencies", nil)]
        )
      end
      let(:content) do
        <<~JSON
          {
            "dependencies": {"is-number":"github:jonschlinkert/is-number#6.0.0"}
          }
        JSON
      end

      it "replaces the git reference" do
        expect(updated_content).to eq(content.sub('"github:jonschlinkert/is-number#6.0.0"', '"^7.0.0"'))
      end
    end

    context "with formatting variants" do
      {
        "a minified document" => '{"name":"app","dependencies":{"etag":"1.0.1","is-number":"6.0.0"}}',
        "extra spaces around the colon" => %({\n  "dependencies": {\n    "is-number"  :   "6.0.0"\n  }\n}\n),
        "entries on one line" =>
          %({\n  "dependencies": { "etag": "1.0.1", "is-number": "6.0.0", "left-pad": "1.3.0" }\n}\n),
        "devDependencies before dependencies" =>
          %({\n  "devDependencies": { "etag": "1.0.1" },\n  "dependencies": {\n    "is-number": "6.0.0"\n  }\n}\n),
        "tab indentation" => %({\n\t"dependencies": {\n\t\t"is-number": "6.0.0"\n\t}\n}\n)
      }.each do |description, document|
        context "with #{description}" do
          let(:content) { document }

          it "updates only the requirement" do
            expect(updated_content).to eq(content.sub('"6.0.0"', '"7.0.0"'))
          end
        end
      end
    end

    context "when a peer dependency has the same requirement" do
      let(:groups) { ["devDependencies"] }
      let(:content) do
        <<~JSON
          {
            "peerDependencies": { "is-number": "6.0.0" },
            "devDependencies": { "is-number": "6.0.0" }
          }
        JSON
      end

      it "updates the peer dependency too" do
        expect(updated_content).to eq(content.gsub('"6.0.0"', '"7.0.0"'))
      end
    end

    context "with resolutions" do
      context "when the resolution pins the previous version" do
        let(:content) do
          <<~JSON
            {
              "dependencies": { "is-number": "6.0.0" },
              "resolutions": { "is-number": "6.0.0" }
            }
          JSON
        end

        it "updates the declaration and the resolution" do
          expect(updated_content).to eq(content.gsub('"6.0.0"', '"7.0.0"'))
        end
      end

      context "when pnpm overrides pin the previous version" do
        let(:content) do
          <<~JSON
            {
              "dependencies": { "is-number": "6.0.0" },
              "pnpm": { "overrides": { "is-number": "6.0.0" } }
            }
          JSON
        end

        it "updates the declaration and the override" do
          expect(updated_content).to eq(content.gsub('"6.0.0"', '"7.0.0"'))
        end
      end

      context "when top-level overrides pin the previous version" do
        let(:content) do
          <<~JSON
            {
              "dependencies": { "is-number": "6.0.0" },
              "overrides": { "is-number": "6.0.0" }
            }
          JSON
        end

        it "updates the declaration and the override" do
          expect(updated_content).to eq(content.gsub('"6.0.0"', '"7.0.0"'))
        end
      end

      context "when unrelated resolutions precede the overrides" do
        let(:content) do
          <<~JSON
            {
              "dependencies": { "is-number": "6.0.0" },
              "resolutions": { "etag": "1.0.1" },
              "overrides": { "is-number": "6.0.0" }
            }
          JSON
        end

        it "updates the declaration and the override" do
          expect(updated_content).to eq(content.gsub('"6.0.0"', '"7.0.0"'))
        end
      end

      context "when unrelated resolutions precede pnpm overrides" do
        let(:content) do
          <<~JSON
            {
              "dependencies": { "is-number": "6.0.0" },
              "resolutions": { "etag": "1.0.1" },
              "pnpm": { "overrides": { "is-number": "6.0.0" } }
            }
          JSON
        end

        it "updates the declaration and the override" do
          expect(updated_content).to eq(content.gsub('"6.0.0"', '"7.0.0"'))
        end
      end

      context "when the resolution is the previous requirement" do
        let(:content) do
          <<~JSON
            {
              "dependencies": { "is-number": "^6.0.0" },
              "resolutions": { "is-number": "^6.0.0" }
            }
          JSON
        end
        let(:previous_requirement) { "^6.0.0" }
        let(:new_requirement) { "^7.0.0" }

        it "updates the resolution to the new requirement" do
          expect(updated_content).to eq(content.gsub('"^6.0.0"', '"^7.0.0"'))
        end
      end

      context "when resolutions and overrides pin the dependency differently" do
        let(:content) do
          <<~JSON
            {
              "dependencies": { "is-number": "^6.0.0" },
              "resolutions": { "is-number": "^6.0.0" },
              "overrides": { "is-number": "6.0.0" }
            }
          JSON
        end
        let(:previous_requirement) { "^6.0.0" }
        let(:new_requirement) { "^7.0.0" }

        it "updates each entry from its own value" do
          expect(updated_content).to eq(content.gsub('"^6.0.0"', '"^7.0.0"').sub('"6.0.0"', '"7.0.0"'))
        end
      end

      context "when the resolution is compact" do
        let(:content) do
          <<~JSON
            {
              "dependencies": { "is-number": "6.0.0" },
              "resolutions": {"etag":"1.0.1","is-number":"6.0.0"}
            }
          JSON
        end

        it "updates the declaration and the resolution" do
          expect(updated_content).to eq(content.gsub('"6.0.0"', '"7.0.0"'))
        end
      end

      context "when a compact declaration with the same requirement precedes the resolution" do
        let(:content) do
          <<~JSON
            {
              "dependencies": { "is-number": "^6.0.0" },
              "workspaces": {"packages":["packages/*"],"catalog":{"is-number":"6.0.0"}},
              "resolutions": { "is-number": "6.0.0" }
            }
          JSON
        end
        let(:previous_requirement) { "^6.0.0" }
        let(:new_requirement) { "^7.0.0" }

        it "updates the resolution" do
          expect(updated_content).to eq(
            content.sub('"^6.0.0"', '"^7.0.0"').sub('"is-number": "6.0.0"', '"is-number": "7.0.0"')
          )
        end
      end

      context "when the resolution key is a package path" do
        let(:content) do
          <<~JSON
            {
              "dependencies": { "is-number": "^6.0.0" },
              "resolutions": { "**/is-number": "6.0.0" }
            }
          JSON
        end
        let(:previous_requirement) { "^6.0.0" }
        let(:new_requirement) { "^7.0.0" }

        it "updates the resolution" do
          expect(updated_content).to eq(content.sub('"^6.0.0"', '"^7.0.0"').sub('"6.0.0"', '"7.0.0"'))
        end
      end

      context "when a nested overrides object declares the same requirement" do
        let(:content) do
          <<~JSON
            {
              "dependencies": { "is-number": "^6.0.0" },
              "workspaces": { "packages": ["packages/*"], "catalogs": { "overrides": { "is-number": "6.0.0" } } },
              "resolutions": { "is-number": "6.0.0" }
            }
          JSON
        end
        let(:previous_requirement) { "^6.0.0" }
        let(:new_requirement) { "^7.0.0" }

        it "updates only the resolution" do
          expect(updated_content).to eq(
            content.sub('"^6.0.0"', '"^7.0.0"')
                   .sub('"resolutions": { "is-number": "6.0.0" }', '"resolutions": { "is-number": "7.0.0" }')
          )
        end
      end
    end
  end
end
