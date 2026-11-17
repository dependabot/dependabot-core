# typed: false
# frozen_string_literal: true

module NodeRuntimeSpecHelper
  def stub_node_runtime(major)
    directory = ENV.fetch("DEPENDABOT_TEST_NODE_#{major}", nil)
    unless directory
      raise "DEPENDABOT_TEST_NODE_#{major} is required in CI" if ENV["CI"]

      skip "Set DEPENDABOT_TEST_NODE_#{major} to a Node #{major} installation directory"
    end

    node = File.join(directory, "bin", "node")
    version = Dependabot::SharedHelpers.run_shell_command([node, "-v"], fingerprint: "test node -v").strip
    raise "Expected Node #{major}, got #{version}" unless version.match?(/\Av#{major}\.\d+\.\d+\z/)

    allow(ENV).to receive(:key?).and_call_original
    allow(ENV).to receive(:key?).with("NVM_DIR").and_return(true)
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).and_call_original
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      ["bash", "/opt/node-version-manager", "list"], fingerprint: "nvm ls-remote"
    ).and_return("#{version}\n")
    allow(Dependabot::SharedHelpers).to receive(:run_shell_command).with(
      ["bash", "/opt/node-version-manager", "install", version.delete_prefix("v")],
      fingerprint: "nvm install <version>",
      stderr_to_stdout: false
    ).and_return("#{node}\n")
  end
end
