#!/bin/bash
# shellcheck disable=all

nuget_experiment_value=$(cat "$DEPENDABOT_JOB_PATH" | jq '.job.experiments.nuget_native_updater')
echo "NuGet native updater experiment value: $nuget_experiment_value"

if echo "$nuget_experiment_value" | grep -q 'true'; then
    pwsh "$DEPENDABOT_HOME/dependabot-updater/bin/main.ps1" $*
else
    "$DEPENDABOT_HOME/dependabot-updater/bin/run-original" $*
fi
