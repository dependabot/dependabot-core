## `dependabot-azure_pipelines`

Azure Pipelines support for [`dependabot-core`][core-repo].

Updates the `task:` steps in Azure Pipelines YAML:

```yaml
steps:
  - task: Maven@3   # ->  - task: Maven@4
```

### How task versions are resolved

Azure Pipelines pins the *major* version of a task and lets the agent pick up newer
minors and patches on its own, so the update this ecosystem offers is normally a major
bump. A [fully pinned version][task-versions] such as `GoTool@0.3.1` is also valid, and
is updated in full.

Versions are compared and rewritten at the precision the pipeline used. Without that,
`Maven@4` would look out of date against a newest release of `4.276.0` and produce a
pull request that changed nothing.

Tasks are installed per Azure DevOps organization, and the API that reports what an
organization has (`_apis/distributedtask/tasks`) needs credentials for that
organization. Dependabot has no such credentials — an Azure Pipelines YAML file can
just as easily live in a GitHub repository — so versions come from
[`microsoft/azure-pipelines-tasks`][tasks-repo] instead, resolved at its latest
published release rather than its default branch. Releases lag the branch, which is
the point: Azure DevOps rolls tasks out over sprints, so a released tag is closer to
what organizations can actually run.

### Known limitations

- **Marketplace and custom tasks are left alone.** A task from a Marketplace extension
  (`SonarQubePrepare@7`, say) has no directory in the tasks repository, and the
  Marketplace API exposes extension versions rather than task versions. Nothing is
  proposed for them.
- **Tasks referenced by GUID are left alone**, for the same reason: there is no
  affordable way to map a GUID back to a directory.
- **Deprecated majors are never proposed as a target.** A pipeline already sitting on
  one keeps it rather than being rewritten to itself.
- **A proposed version may briefly not exist for every organization**, because task
  rollout is staged across deployment rings.

### Running locally

1. Start a development shell

  ```
  $ bin/docker-dev-shell azure_pipelines
  ```

2. Run tests
   ```
   [dependabot-core-dev] ~ $ cd azure_pipelines && rspec
   ```

[core-repo]: https://github.com/dependabot/dependabot-core
[tasks-repo]: https://github.com/microsoft/azure-pipelines-tasks
[task-versions]: https://learn.microsoft.com/en-us/azure/devops/pipelines/process/tasks#task-versions
