# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"

module Dependabot
  module AzurePipelines
    ECOSYSTEM = T.let("azure-pipelines", String)
    PACKAGE_MANAGER = T.let("azure_pipelines", String)

    # Azure Pipelines installs tasks per Azure DevOps organization, and the API that
    # reports them (`_apis/distributedtask/tasks`) requires organization credentials.
    # The tasks Microsoft ships are developed in the open, so we use that repository
    # as a credential-free source of truth instead.
    TASKS_REPO = T.let("microsoft/azure-pipelines-tasks", String)
    TASKS_REPO_URL = T.let("https://github.com/#{TASKS_REPO}".freeze, String)
    TASKS_API_URL = T.let("https://api.github.com/repos/#{TASKS_REPO}".freeze, String)
    TASKS_RAW_URL = T.let("https://raw.githubusercontent.com/#{TASKS_REPO}".freeze, String)

    # Tasks live in `Tasks/<Name>V<major>`, one directory per major version. The
    # directory name is a convention rather than a guarantee: `ANTV1` declares
    # `"name": "Ant"`, so it is only ever used to narrow the candidates, and the
    # `task.json` it contains decides the match.
    TASKS_DIRECTORY = T.let("Tasks", String)

    # Fall back to the default branch when no release has been published. Releases lag
    # the default branch by design, which is what we want: they are closer to what
    # Azure DevOps has actually rolled out.
    DEFAULT_REF = T.let("master", String)

    # A step references a task as `<name>@<version>`, where the name is either a task
    # name or the task's GUID.
    TASK_REFERENCE_PATTERN = T.let(/\A(?<name>[^@\s]+)@(?<version>[^@\s]+)\z/, Regexp)

    # Only the major version is required. `PublishTestResults@2` is by far the most
    # common form, but a full version such as `GoTool@0.3.1` is also valid.
    TASK_VERSION_PATTERN = T.let(/\A\d+(?:\.\d+){0,2}\z/, Regexp)

    # Task names and versions can be built from template expressions (`${{ ... }}`,
    # `$( ... )`), which cannot be resolved without running the pipeline.
    TEMPLATE_EXPRESSION_PATTERN = T.let(/\$[({]/, Regexp)
  end
end
