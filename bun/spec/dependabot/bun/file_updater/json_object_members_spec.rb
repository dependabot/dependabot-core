# typed: false
# frozen_string_literal: true

require "spec_helper"
require "dependabot/bun/file_updater/json_object_members"

RSpec.describe Dependabot::Bun::FileUpdater::JsonObjectMembers do
  subject(:members) { described_class.find(content, content.index("{")).transform_values { |range| content[range] } }

  let(:content) do
    <<~JSON
      {
        "scripts": { "build": "echo ${OUT} } { \\" \\\\", "list": "[" },
        "workspaces": ["packages/*"],
        "name": "example",
        "catalogs": { "catalog": { "react": "^19.0.0" }, "t\\u0065sting": { "jest": "30.0.0" } },
        "catalog": { "react": "^19.0.0" }
      }
    JSON
  end

  it "maps only direct object members to their source text" do
    expect(members).to eq(
      "scripts" => '{ "build": "echo ${OUT} } { \" \\\\", "list": "[" }',
      "catalogs" => '{ "catalog": { "react": "^19.0.0" }, "t\u0065sting": { "jest": "30.0.0" } }',
      "catalog" => '{ "react": "^19.0.0" }'
    )
  end

  it "scans a nested object from its opening brace" do
    nested = described_class.find(content, content.index('{ "catalog"'))

    expect(nested.transform_values { |range| content[range] }).to eq(
      "catalog" => '{ "react": "^19.0.0" }',
      "testing" => '{ "jest": "30.0.0" }'
    )
  end
end
