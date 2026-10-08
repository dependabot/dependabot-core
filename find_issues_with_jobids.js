#!/usr/bin/env node

/**
 * This script searches for open issues in the dependabot/dependabot-core repository
 * where a job ID (10-digit number) is mentioned in the opening comment.
 * 
 * Usage:
 *   GITHUB_TOKEN=your_token node find_issues_with_jobids.js
 * 
 * The script will:
 * 1. Fetch all open issues from the repository
 * 2. Search for 10-digit numbers (job IDs) in the issue body
 * 3. Output a text file with URLs of matching issues
 */

const https = require('https');
const fs = require('fs');

const REPO_OWNER = 'dependabot';
const REPO_NAME = 'dependabot-core';
const GITHUB_API_TOKEN = process.env.GITHUB_TOKEN || process.env.DEPENDABOT_TEST_ACCESS_TOKEN;

// Pattern to match job IDs - a 10-digit number
const JOB_ID_PATTERN = /\b\d{10}\b/g;

/**
 * Fetch issues from GitHub API
 * @param {number} page - Page number for pagination
 * @param {number} perPage - Number of results per page
 * @returns {Promise<Array>} Array of issues
 */
function fetchIssues(page = 1, perPage = 100) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.github.com',
      path: `/repos/${REPO_OWNER}/${REPO_NAME}/issues?state=open&per_page=${perPage}&page=${page}`,
      method: 'GET',
      headers: {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'dependabot-jobid-finder'
      }
    };

    if (GITHUB_API_TOKEN) {
      options.headers['Authorization'] = `Bearer ${GITHUB_API_TOKEN}`;
    }

    const req = https.request(options, (res) => {
      let data = '';

      res.on('data', (chunk) => {
        data += chunk;
      });

      res.on('end', () => {
        if (res.statusCode === 200) {
          resolve(JSON.parse(data));
        } else {
          reject(new Error(`Error fetching issues: ${res.statusCode} ${res.statusMessage}\n${data}`));
        }
      });
    });

    req.on('error', (error) => {
      reject(error);
    });

    req.end();
  });
}

/**
 * Find all issues that contain job IDs in their body
 * @returns {Promise<Array>} Array of issues with job IDs
 */
async function findIssuesWithJobIds() {
  const issuesWithJobIds = [];
  let page = 1;

  while (true) {
    console.log(`Fetching page ${page}...`);
    
    try {
      const issues = await fetchIssues(page);
      
      if (issues.length === 0) {
        break;
      }

      for (const issue of issues) {
        // Skip pull requests
        if (issue.pull_request) {
          continue;
        }

        const body = issue.body || '';
        const jobIds = body.match(JOB_ID_PATTERN);
        
        if (jobIds && jobIds.length > 0) {
          issuesWithJobIds.push({
            number: issue.number,
            title: issue.title,
            url: issue.html_url,
            jobIds: [...new Set(jobIds)] // Remove duplicates
          });
        }
      }

      // GitHub API returns at most 100 results per page
      if (issues.length < 100) {
        break;
      }

      page++;
    } catch (error) {
      console.error(`Error on page ${page}:`, error.message);
      break;
    }
  }

  return issuesWithJobIds;
}

/**
 * Main execution function
 */
async function main() {
  console.log(`Searching for open issues with job IDs in ${REPO_OWNER}/${REPO_NAME}...`);
  
  try {
    const issues = await findIssuesWithJobIds();

    if (issues.length === 0) {
      console.log('No issues found with job IDs.');
      return;
    }

    console.log(`\nFound ${issues.length} issue(s) with job IDs:\n`);

    // Create output text file with URLs
    const outputLines = [];
    
    for (const issue of issues) {
      console.log(`#${issue.number}: ${issue.title}`);
      console.log(`  URL: ${issue.url}`);
      console.log(`  Job IDs: ${issue.jobIds.join(', ')}`);
      console.log('');
      
      outputLines.push(issue.url);
    }

    fs.writeFileSync('issues_with_jobids.txt', outputLines.join('\n') + '\n');
    console.log('URLs saved to issues_with_jobids.txt');

  } catch (error) {
    console.error('Error:', error.message);
    process.exit(1);
  }
}

// Run the script if executed directly
if (require.main === module) {
  main();
}

// Export for potential reuse
module.exports = { findIssuesWithJobIds, fetchIssues };
