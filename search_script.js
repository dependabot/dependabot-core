// Node.js script to search for open issues with 10-digit job IDs in dependabot/dependabot-core
// Install dependencies: npm install @octokit/rest

const { Octokit } = require("@octokit/rest");
const fs = require("fs");

// Initialize Octokit with authentication
const octokit = new Octokit({
  auth: process.env.GITHUB_TOKEN // Set this environment variable with your GitHub token
});

// Function to find 10-digit job IDs in text
function find10DigitJobIds(text) {
  if (!text) return [];
  
  // Match standalone 10-digit numbers (not part of longer numbers)
  const pattern = /\b\d{10}\b/g;
  const matches = text.match(pattern);
  
  return matches ? [...new Set(matches)] : [];
}

// Main function to search for issues
async function searchIssuesWithJobIds() {
  try {
    console.log("Searching for open issues with 10-digit job IDs...\n");
    
    // Search for open issues in the repository
    const issues = await octokit.paginate(octokit.rest.issues.listForRepo, {
      owner: "dependabot",
      repo: "dependabot-core",
      state: "open",
      per_page: 100
    });
    
    const issuesWithJobIds = [];
    
    // Check each issue's body for 10-digit job IDs
    for (const issue of issues) {
      // Skip pull requests
      if (issue.pull_request) continue;
      
      const jobIds = find10DigitJobIds(issue.body);
      
      if (jobIds.length > 0) {
        issuesWithJobIds.push({
          number: issue.number,
          title: issue.title,
          url: issue.html_url,
          jobIds: jobIds
        });
      }
    }
    
    // Display results
    console.log(`Found ${issuesWithJobIds.length} issue(s) with 10-digit job IDs:\n`);
    
    issuesWithJobIds.forEach(issue => {
      console.log(`Issue #${issue.number}: ${issue.title}`);
      console.log(`URL: ${issue.url}`);
      console.log(`Job IDs: ${issue.jobIds.join(", ")}`);
      console.log("---");
    });
    
    // Write URLs to file
    const urls = issuesWithJobIds.map(issue => issue.url).join("\n");
    fs.writeFileSync("issue_urls.txt", urls);
    console.log("\nURLs written to issue_urls.txt");
    
    // Write detailed results to JSON file
    fs.writeFileSync("issue_results.json", JSON.stringify(issuesWithJobIds, null, 2));
    console.log("Detailed results written to issue_results.json");
    
  } catch (error) {
    console.error("Error searching issues:", error.message);
    process.exit(1);
  }
}

// Run the script
searchIssuesWithJobIds();
