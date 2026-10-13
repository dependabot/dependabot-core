# typed: strict
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/file_updater/json_object_members"

RSpec.describe Dependabot::Bun::FileUpdater::JsonObjectMembers do
  extend T::Sig

  sig { returns(String) }
  let(:content) do
    <<~JSON
      {
        "scripts": { "build": "echo ${OUT} } { \\" \\\\", "list": "[" },
        "workspaces": ["packages/*"],
        "name": "example",
        "catalogs": { "catalog": { "react": "^19.0.0" }, "t\\u0065sting": { "jest": "30.0.0" } },
        "catalog": {"react":"^19.0.0", "is-\\u006eumber" :  "6.0.0", "jest": {"nested": "1.0.0"}}
      }
    JSON
  end

  sig { params(members: T::Hash[String, T::Range[Integer]]).returns(T::Hash[String, T.nilable(String)]) }
  def source_text(members)
    members.transform_values { |range| content[range] }
  end

  describe ".objects" do
    it "maps only direct object members to their source text" do
      expect(source_text(described_class.objects(content, T.must(content.index("{"))))).to eq(
        "scripts" => '{ "build": "echo ${OUT} } { \" \\\\", "list": "[" }',
        "catalogs" => '{ "catalog": { "react": "^19.0.0" }, "t\u0065sting": { "jest": "30.0.0" } }',
        "catalog" => '{"react":"^19.0.0", "is-\u006eumber" :  "6.0.0", "jest": {"nested": "1.0.0"}}'
      )
    end

    it "scans a nested object from its opening brace" do
      expect(source_text(described_class.objects(content, T.must(content.index('{ "catalog"'))))).to eq(
        "catalog" => '{ "react": "^19.0.0" }',
        "testing" => '{ "jest": "30.0.0" }'
      )
    end
  end

  describe ".strings" do
    it "maps only direct string members to their source text" do
      expect(source_text(described_class.strings(content, T.must(content.index("{"))))).to eq("name" => '"example"')
    end

    it "decodes keys and keeps the value formatting" do
      expect(source_text(described_class.strings(content, T.must(content.index('{"react"'))))).to eq(
        "react" => '"^19.0.0"',
        "is-number" => '"6.0.0"'
      )
    end
  end
end
