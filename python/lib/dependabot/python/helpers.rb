# frozen_string_literal: true

module Dependabot
  module Python
    module Helpers

      def self.replaced_base_url(credentials)
        credentials.
        select { |cred| cred["type"] == "python_index" && cred.fetch("replaces_base", false)}
      end

      def self.install_required_python(python_version)
        return if SharedHelpers.run_shell_command("pyenv versions").include?("\ #{python_version}")

        SharedHelpers.run_shell_command("pyenv install -s #{python_version}")
        SharedHelpers.run_shell_command("pyenv exec pip install --upgrade pip")
        SharedHelpers.run_shell_command("pyenv exec pip install -r" \
                    "#{NativeHelpers.python_requirements_path}")
      end
    end
  end
end