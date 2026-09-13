# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/file_parser/bun_lock"
require "dependabot/bun/file_parser/bun_lock/dependency_type_resolver"

RSpec.describe Dependabot::Bun::FileParser::BunLock::DependencyTypeResolver do
  subject(:production_by_key) do
    described_class.new(workspaces: lockfile.workspaces, records: lockfile.records).production_by_key
  end

  let(:lockfile) { Dependabot::Bun::FileParser::BunLock.new(file) }
  let(:file) { Dependabot::DependencyFile.new(name: "bun.lock", content: content) }

  context "with production and development chains" do
    let(:content) { fixture("projects", "bun", "simple_v1", "bun.lock") }

    it "marks packages reached only through devDependencies as development" do
      expect(production_by_key).to include(
        "@types/bun" => false,
        "bun-types" => false,
        "@types/node" => false,
        "@types/ws" => false,
        "undici-types" => false,
        "etag" => false
      )
    end

    it "marks packages reached through dependencies or peerDependencies as production" do
      expect(production_by_key).to include(
        "fetch-factory" => true,
        "isomorphic-fetch" => true,
        "whatwg-fetch" => true,
        "node-fetch" => true,
        "encoding" => true,
        "iconv-lite" => true,
        "safer-buffer" => true,
        "is-stream" => true,
        "es6-promise" => true,
        "lodash" => true,
        "typescript" => true
      )
    end
  end

  context "with workspaces and nested copies" do
    let(:content) { fixture("projects", "bun", "workspace_dependency_types", "bun.lock") }

    it "resolves copies nested under packages and under workspace names" do
      expect(production_by_key).to eq(
        "debug" => true,
        "debug/ms" => true,
        "app/ms" => true,
        "tool/is-number" => true,
        "ms" => false,
        "is-number" => false
      )
    end
  end

  context "with copies nested under a transitive package" do
    let(:content) { fixture("projects", "bun", "wildcard", "bun.lock") }

    it "prefers the nested copy over the hoisted one" do
      expect(production_by_key).to include(
        "nock/lodash" => true,
        "deep-eql/type-detect" => true,
        "type-detect" => true,
        "@types/bun" => false
      )
    end
  end

  context "with a synthetic lockfile" do
    let(:content) { { "lockfileVersion" => 1, "workspaces" => { "" => root }, "packages" => packages }.to_json }

    def entry(name, dependencies = {})
      ["#{name}@1.0.0", "", { "dependencies" => dependencies }]
    end

    context "when a package is on both a production and a development path" do
      let(:root) { { "dependencies" => { "app" => "*" }, "devDependencies" => { "tool" => "*" } } }
      let(:packages) do
        {
          "app" => entry("app", "shared" => "*"),
          "tool" => entry("tool", "shared" => "*"),
          "shared" => entry("shared")
        }
      end

      it "keeps it production" do
        expect(production_by_key).to eq("app" => true, "shared" => true, "tool" => false)
      end
    end

    context "when packages depend on each other" do
      let(:root) { { "devDependencies" => { "a" => "*" } } }
      let(:packages) { { "a" => entry("a", "b" => "*"), "b" => entry("b", "a" => "*") } }

      it "visits each package once" do
        expect(production_by_key).to eq("a" => false, "b" => false)
      end
    end

    context "when a copy is nested under a scoped package" do
      let(:root) { { "devDependencies" => { "@scope/parent" => "*" } } }
      let(:packages) do
        {
          "@scope/parent" => entry("@scope/parent", "child" => "*"),
          "@scope/parent/child" => entry("child"),
          "child" => entry("child")
        }
      end

      it "treats the scoped name as one level" do
        expect(production_by_key).to eq("@scope/parent" => false, "@scope/parent/child" => false)
      end
    end

    context "when the closest nested copy is further up the tree" do
      let(:root) { { "dependencies" => { "a" => "*" } } }
      let(:packages) do
        {
          "a" => entry("a", "b" => "*"),
          "a/b" => entry("b", "c" => "*"),
          "a/c" => entry("c"),
          "c" => entry("c")
        }
      end

      it "moves up one level at a time" do
        expect(production_by_key).to eq("a" => true, "a/b" => true, "a/c" => true)
      end
    end

    context "when a dependency is missing from packages" do
      let(:root) { { "dependencies" => { "a" => "*" } } }
      let(:packages) { { "a" => entry("a", "optional-peer" => "*"), "orphan" => entry("orphan") } }

      it "skips it and leaves unreached packages out" do
        expect(production_by_key).to eq("a" => true)
      end
    end
  end
end
