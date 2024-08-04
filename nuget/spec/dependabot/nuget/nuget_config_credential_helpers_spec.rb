# typed: false
# frozen_string_literal: true

require "dependabot/nuget/nuget_config_credential_helpers"

RSpec.describe Dependabot::Nuget::NuGetConfigCredentialHelpers do
  subject(:result) { user_nuget_config_contents_during_and_after_action }

  let(:user_nuget_config_contents_during_and_after_action) do
    path = described_class.user_nuget_config_path
    content_during_action = nil
    described_class.patch_nuget_config_for_action(credentials) do
      content_during_action = File.read(path)
    end
    content_after_action = File.read(path)
    { content_during_action: content_during_action, content_after_action: content_after_action }
  end

  let(:default_nuget_config_contents) do
    File.read(described_class.user_nuget_config_path)
  end

  describe "user level NuGet.Config patching" do
    context "with an empty credential set" do
      let(:credentials) { [] }

      it "does not change the contents of the file" do
        expect(result[:content_during_action]).to eq(default_nuget_config_contents)
        expect(result[:content_after_action]).to eq(default_nuget_config_contents)
      end
    end

    context "with non-empty credential set" do
      let(:credentials) do
        [
          { "type" => "not_nuget", "some_other_field" => "some other value" },
          { "type" => "nuget_feed", "url" => "https://public1.nuget.example.com/index.json" },
          { "type" => "nuget_feed", "url" => "https://private2.nuget.example.com/index.json",
            "username" => "user", "password" => "secret" },
          { "type" => "nuget_feed", "url" => "https://private3.nuget.example.com/index.json",
            "password" => "secret" },
          { "type" => "nuget_feed", "url" => "https://private4.nuget.example.com/index.json",
            "token" => "PAT:12345" },
          { "type" => "nuget_feed", "url" => "https://private5.nuget.example.com/index.json",
            "token" => ":12345" },
          { "type" => "nuget_feed", "url" => "https://private6.nuget.example.com/index.json",
            "token" => "12345" },
          { "type" => "nuget_feed", "url" => "https://private7.nuget.example.com/index.json",
            "token" => Base64.encode64("PAT:12345").delete("\n") },
          { "type" => "nuget_feed", "url" => "https://private8.nuget.example.com/index.json",
            "token" => Base64.encode64(":12345").delete("\n") },
          { "type" => "nuget_feed", "url" => "https://private9.nuget.example.com/index.json",
            "token" => Base64.encode64("12345").delete("\n") }
        ]
      end

      context "with credentials given" do
        it "changes the content of the config file, then changes it back" do
          expect(result[:content_during_action]).to eq(
            <<~XML
              <?xml version="1.0" encoding="utf-8"?>
              <configuration>
                <packageSources>
                  <add key="nuget_source_1" value="https://public1.nuget.example.com/index.json" />
                  <add key="nuget_source_2" value="https://private2.nuget.example.com/index.json" />
                  <add key="nuget_source_3" value="https://private3.nuget.example.com/index.json" />
                  <add key="nuget_source_4" value="https://private4.nuget.example.com/index.json" />
                  <add key="nuget_source_5" value="https://private5.nuget.example.com/index.json" />
                  <add key="nuget_source_6" value="https://private6.nuget.example.com/index.json" />
                  <add key="nuget_source_7" value="https://private7.nuget.example.com/index.json" />
                  <add key="nuget_source_8" value="https://private8.nuget.example.com/index.json" />
                  <add key="nuget_source_9" value="https://private9.nuget.example.com/index.json" />
                </packageSources>
                <packageSourceCredentials>
                  <nuget_source_2>
                    <add key="Username" value="user" />
                    <add key="ClearTextPassword" value="secret" />
                  </nuget_source_2>
                  <nuget_source_3>
                    <add key="Username" value="unused" />
                    <add key="ClearTextPassword" value="secret" />
                  </nuget_source_3>
                  <nuget_source_4>
                    <add key="Username" value="PAT" />
                    <add key="ClearTextPassword" value="12345" />
                  </nuget_source_4>
                  <nuget_source_5>
                    <add key="Username" value="unused" />
                    <add key="ClearTextPassword" value="12345" />
                  </nuget_source_5>
                  <nuget_source_6>
                    <add key="Username" value="unused" />
                    <add key="ClearTextPassword" value="12345" />
                  </nuget_source_6>
                  <nuget_source_7>
                    <add key="Username" value="PAT" />
                    <add key="ClearTextPassword" value="12345" />
                  </nuget_source_7>
                  <nuget_source_8>
                    <add key="Username" value="unused" />
                    <add key="ClearTextPassword" value="12345" />
                  </nuget_source_8>
                  <nuget_source_9>
                    <add key="Username" value="unused" />
                    <add key="ClearTextPassword" value="MTIzNDU=" />
                  </nuget_source_9>
                </packageSourceCredentials>
              </configuration>
            XML
          )
          expect(result[:content_after_action]).to eq(default_nuget_config_contents)
        end
      end

      context "when exception is raised" do
        it "restores the original file after an exception" do
          described_class.patch_nuget_config_for_action(credentials) do
            raise "This exception was raised when the NuGet.Config file was patched"
          end
          nuget_config_content = File.read(described_class.user_nuget_config_path)
          expect(nuget_config_content).to eq(default_nuget_config_contents)
        end
      end
    end
  end
end
