""" Fetches the upstream changes/commits, merged them
    in the feature branch in forked repository and open
    the PR against forked master branch
"""

import argparse
import git
import os
import sys

from github import Github, GithubException

COMMITER = "Pix4D-Janus"
COMMITER_EMAIL = "platform_ci_team@pix4d.com"
PR_MESSAGE = "Merge the upstream changes"
MONITORED_REPO = "pix4d/dependabot-core"

access_token = os.environ["REPOSITORY_ACCESS_TOKEN"]

parser = argparse.ArgumentParser()
parser.add_argument("--tag", required=True, help="Upstream tag")
parser.add_argument("--timestamp", required=True, help="Timestamp")

args = parser.parse_args()

branch_name = f"upstream_{args.tag}_{args.timestamp}"

repo = git.Repo(os.curdir)

repo.config_writer().set_value("user", "email", COMMITER_EMAIL).release()
repo.config_writer().set_value("user", "name", COMMITER).release()

git.Repo(os.curdir).create_remote("upstream", url="../upstream-dependabot-core.git")
repo.git.checkout("-b", branch_name)
repo.git.pull("upstream", "master")

changed_files = [item.a_path for item in repo.head.commit.diff('HEAD~1')]

if not changed_files:
    print("No files were changed.")
    sys.exit(0)

correct_files = any([filename.startswith('docker/') for filename in changed_files])

if correct_files:
    pr_title = "[changes-to-pix4d-dependabot] Merge the upstream changes"
else:
    pr_title = "[no-changes-to-pix4d-dependabot] Merge the upstream changes"

repo.git.push("--set-upstream", "origin", branch_name)

pr = (
    Github(access_token)
    .get_repo(MONITORED_REPO)
    .create_pull(title=pr_title, base="master", head=branch_name, body=PR_MESSAGE,)
)
print(pr.html_url)
