""" For a commit that triggered the job, verify that all the checks successfully
finished before trying to merge the upstream changes. Upstream checks can take up
to 30 minutes, so we check multiple times (max 10), and wait 150 sec between the 
attempts.
"""

import argparse
import logging
import sys
import time

import requests

WAIT_TIME = 150

logger = logging.getLogger("check-upstream-status")
logging.basicConfig(level=logging.INFO)

parser = argparse.ArgumentParser()
parser.add_argument("--commit", required=True, help="Upstream commit hash")
# Github repository access token is used to avoid errors due to API rate limits
parser.add_argument("--token", required=True, help="Github repository access token")
args = parser.parse_args()

num_check = 0
max_checks = 10

while num_check < max_checks:
    num_check += 1
    jobs = []
    job_status = []
    status_filter = []
    data = requests.get(
        f"https://api.github.com/repos/dependabot/dependabot-core/commits/{args.commit}/check-runs",
        headers={"authorization":f"Bearer {args.token}", "Accept": "application/vnd.github.antiope-preview+json"},
    )
    if data.status_code != requests.codes.ok:
        logger.error("HTTP request failed ")
        logger.info(f"Waiting before checking upstream status again. This was attempt number: {num_check}")
        time.sleep(WAIT_TIME)
        continue

    response = data.json()
    job_status = [ (check_run["status"],check_run["conclusion"]) for check_run in response["check_runs"] ]
    all_ok = all(item == ('completed', 'success') for item in job_status)
    
    if all_ok:
        msg = f"Check the details here: https://github.com/dependabot/dependabot-core/commit/{args.commit}"
        logger.info(msg)
        logger.info("All " + str(response["total_count"]) + " checks finished successfully")
        sys.exit(0)

    logger.info(f"Waiting before checking upstream status again. This was attempt number: {num_check}")
    time.sleep(WAIT_TIME)

for check_run in response["check_runs"]:
    if check_run["status"] != "completed" or check_run["conclusion"] != "success":
        logger.error(f"Job name: {check_run['name']} status: {check_run['status']}, conclusion: {check_run['conclusion']}")

msg = f"Check the details here: https://github.com/dependabot/dependabot-core/commit/{args.commit}" 
logger.error("Some checks failed in the upstream repository")
logger.error(msg)

sys.exit(1)


