#!/bin/bash

###
### Set inputs
###
max_days_inactive="${{ inputs.max-days-inactive }}"
gh_org="${{ inputs.github-org }}"
GITHUB_TOKEN="${{ inputs.github-pat }}"


###
### Date
###
current_date_in_epoc=$(date +%s)
number_of_seconds_in_a_month=$((60 * 60 * 24 * $max_days_inactive))
date_one_month_ago=$(($current_date_in_epoc - $number_of_seconds_in_a_month))


###
### Functions
###

# Hold until rate-limit success
hold_until_rate_limit_success() {
  
  # Loop forever
  while true; do
    
    # Any call to AWS returns rate limits in the response headers
    API_RATE_LIMIT_UNITS_REMAINING=$(curl -sv \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      https://api.github.com/repos/$gh_org/ActionPRValidate_AnyJobRun/autolinks 2>&1 1>/dev/null \
      | grep -E '< x-ratelimit-remaining' \
      | cut -d ' ' -f 3 \
      | xargs \
      | tr -d '\r')

    # If API rate-limiting is hit, sleep for 1 minute
    # Rounded parenthesis are used to trigger arithmetic expansion, which compares more than the first numeric digit (bash is weird)
    if (( "$API_RATE_LIMIT_UNITS_REMAINING" < 100 )); then
      echo "ℹ️  We have less than 100 GitHub API rate-limit tokens left ($API_RATE_LIMIT_UNITS_REMAINING), sleeping for 1 minute"
      sleep 60
    
    # If API rate-limiting shows remaining units, break out of loop and function
    else  
      echo "💥 Rate limit checked, we have "$API_RATE_LIMIT_UNITS_REMAINING" core tokens remaining so we are continuing"
      break
    fi

  done
}

# Remove user from copilot
remove_user_from_copilot() {
  
  REMOVE_USER_FROM_COPILOT=$(curl -sL \
    -X DELETE \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $GITHUB_TOKEN" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/orgs/$gh_org/copilot/billing/selected_users \
    -d "{\"selected_usernames\":[\"$copilot_user\"]}")

    # If response contains json key seats_cancelled, it worked
    if [[ $REMOVE_USER_FROM_COPILOT == *"seats_cancelled"* ]]; then
      echo "✅ User $copilot_user removed from CoPilot"
    else
      echo "❌ Failed to remove user $copilot_user from CoPilot, please investigate:"
      echo "$REMOVE_USER_FROM_COPILOT"
    fi

}


###
### Fetch data to iterate over
###

# Get all the copilot user data
copilot_all_user_data=$(curl -s \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/orgs/$gh_org/copilot/billing/seats?per_page=100 2>&1)

# Get all users that are added to CoPilot
copilot_all_users=$(echo "$copilot_all_user_data" | jq -r '.seats[].assignee.login')


###
### Iterate over users, identify which ones to keep active vs deactivate
###

# Iterate through all users, check their last active date
while IFS=$'\n' read -r copilot_user; do
  
  # Print divider
  echo "****************************************"

  # Check rate limit blockers, hold if token bucket too low
  hold_until_rate_limit_success

  # Print the user we're looking at
  echo "🔍 Looking into $copilot_user"

  # Filter for user's data block
  user_data=$(echo "$copilot_all_user_data" | jq -r ".seats[] | select(.assignee.login==\"$copilot_user\")")

  # Check if already cancellation set
  pending_cancellation_date=$(echo "$user_data" | jq -r '.pending_cancellation_date')
  # If cancellation date null, print hi
  if [ "$pending_cancellation_date" == "null" ]; then
    echo "No pending cancellation date"
  else
    echo "User is already scheduled for deactivation, skipping, user license will be disabled: $pending_cancellation_date"
    continue
  fi

  # Get the created date of the user
  created_at_date=$(echo "$user_data" | jq -r '.created_at')
  echo "Created at date: $created_at_date"

  # Convert the created date to epoc
  # This uses branching logic because macs don't use GNUtils date
  if [ -z "$local_testing" ]; then
    created_date_in_epoc=$(date -d $created_at_date +"%s")
  else
    created_date_in_epoc=$(date -juf "%Y-%m-%dT%H:%M:%S" $created_at_date +%s 2>/dev/null)
  fi
  
  # Get the last editor of the user
  last_editor=$(echo "$user_data" | jq -r '.last_activity_editor')
  echo "Last editor: $last_editor"

   # Get the last active date of the user
  last_active_date=$(echo "$user_data" | jq -r '.last_activity_at')
  echo "Last activity date at: $last_active_date"

  # Check if last_active_date is null
  if [ "$last_active_date" == "null" ]; then

    echo "🔴 User $copilot_user has never been active"

    # If created date more than a month ago, then user is inactive
    if (( $created_date_in_epoc < $date_one_month_ago )); then
      echo "🔴 User $copilot_user is inactive and was created more than a month ago, disabling user"
      remove_user_from_copilot
    else
      echo "🟢 User $copilot_user is not active yet, but was created in the last month. Leaving active."
    fi
  
    continue
  fi

  # Convert the last active date to epoc
  # This uses branching logic because macs don't use GNUtils date
  if [ -z "$local_testing" ]; then
    last_active_date_in_epoc=$(date -d $last_active_date +"%s")
  else
    last_active_date_in_epoc=$(date -juf "%Y-%m-%dT%H:%M:%S" $last_active_date +%s 2>/dev/null)
  fi
  
  # Check if the last active date epoc is less than a month ago
  if (( $last_active_date_in_epoc < $date_one_month_ago )); then
    echo "🔴 User $copilot_user is inactive for more than a month, disabling copilot for user"
    remove_user_from_copilot
    continue
  else
    echo "🟢 User $copilot_user is active in the last month"
  fi

done <<< "$copilot_all_users"

# Finish
echo ""
echo "################"
echo "Done!"
echo "################"
exit 0