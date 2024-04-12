# CleanupCopilotLicenses

This Action can be run against an Organization to remove CoPilot licenses from users who have not committed code in a specified number of days.

Make sure the PAT for the user you are providing has SSO authorization to run against the Org you're targeting, and will require manage_billing:copilot scope.

This should run on a host with `jq` and `curl` installed. The ubuntu-latest host does have these tools. 

# Example call of this action

```
name: Cleanup CoPilot Licenses

on:
  # Run automatically when master updated
  push:
    branches: 
    - master
  # Run nightly at 5a UTC / 11p CT
  schedule:
  - cron: "0 5 * * *"
  # Permit manual trigger
  workflow_dispatch:

jobs:
  cleanup_copilot_licenses:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3

    - name: Copilot License Cleanup
      id: jira_commit_checker
      uses: kymidd/CleanupCopilotLicenses@v1
      with:
        github-org: "your-org-name"
        github-pat: ${{ secrets.PAT_NAME_HERE }}
        max-days-inactive: "30"
```