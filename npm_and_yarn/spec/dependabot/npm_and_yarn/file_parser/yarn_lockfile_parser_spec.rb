# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency_file"
require "dependabot/npm_and_yarn/file_parser/yarn_lockfile_parser"

RSpec.describe Dependabot::NpmAndYarn::FileParser::YarnLockfileParser do
  before do
    Dependabot::Experiments.register(:yarn_berry, true)
  end

  subject(:yarn_lockfile_parser) do
    described_class.new(lockfile: yarn_lockfile)
  end
  let(:yarn_lockfile) do
    project_dependency_files(project_name).find { |f| f.name == "yarn.lock" }
  end
  let(:project_name) { "yarn/other_package" }

  describe "#parse" do
    subject(:lockfile) { yarn_lockfile_parser.parse }

    it "parses the lockfile" do
      expect(lockfile).to eq(
        "etag@^1.0.0" => {
          "version" => "1.8.0",
          "resolved" => "https://registry.yarnpkg.com/etag/-/etag-" \
                        "1.8.0.tgz#41ae2eeb65efa62268aebfea83ac7d79299b0111"
        },
        "lodash@^1.2.1" => {
          "version" => "1.3.1",
          "resolved" => "https://registry.yarnpkg.com/lodash/-/lodash-" \
                        "1.3.1.tgz#a4663b53686b895ff074e2ba504dfb76a8e2b770"
        }
      )
    end

    context "with multiple requirements sharing a version resolution" do
      let(:project_name) { "yarn/file_path_resolutions" }

      it "expands lockfile requirements sharing the same version resolution" do
        first = lockfile.find { |o| o.first == "sprintf-js@~1.0.2" }
        second = lockfile.find do |o|
          o.first == "sprintf-js@file:./mocks/sprintf-js"
        end
        # Share same version requirement
        expect(first.last).to equal(second.last)
        expect(lockfile.map(&:first)).to contain_exactly(
          "argparse@^1.0.7", "esprima@^4.0.0", "js-yaml@^3.13.1",
          "sprintf-js@file:./mocks/sprintf-js", "sprintf-js@~1.0.2"
        )
      end
    end

    context "with invalid lockfile" do
      let(:project_name) { "yarn/bad_content" }

      it "handles the error" do
        expect(lockfile).to eq({})
      end
    end
  end
end
