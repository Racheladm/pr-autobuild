#!/bin/bash

set -Eexo pipefail

function updatePRdetails {
    log "Function updatePRdetails"

    local pr_num
    pr_num=$1

    local prDetails
    prDetails=$(getCall "$GIT_PR_API" "$pr_num")
    PR_BRANCH=$(echo "$prDetails" | jq -r '.head.ref')
    export PR_BRANCH
    BASE_BRANCH=$(echo "$prDetails" | jq -r '.base.ref')
    export BASE_BRANCH
    LABELS=$(echo "$prDetails" | jq -r '.labels')
    export LABELS
}

function getMergeStatus {
    log "Function getMergeStatus"

    local pr_num
    pr_num=$1

    local mergeStatus
    mergeStatus=$(getCall "$GIT_PR_MERGE_API" "$pr_num")

    if [[ "$mergeStatus" == *"Not Found"* ]]; then
        echo "$UNMERGED_STATUS"
    else
        echo "$MERGED_STATUS"
    fi
}

function isPROpenAndUnmerged {
    log "Function isPROpenAndUnmerged"

    local pr_num
    pr_num=$1

    local prDetails
    prDetails=$(getCall "$GIT_PR_API" "$pr_num")
    local prStatus
    prStatus=$(echo "$prDetails" | jq -r '.state')
    local mergeStatus
    mergeStatus=$(getMergeStatus "$pr_num")

    log "Debug: PR status $prStatus of $pr_num"
    log "Debug: Merge status $mergeStatus of $pr_num"

    if [ "$prStatus" == 'open' ] && [ "$mergeStatus" == "$UNMERGED_STATUS" ];
    then 
        echo true
    else 
        echo false
    fi
}

function isApproved {
    log "Function isApproved"

    local approvalCount
    approvalCount=0
    local prStatus
    prStatus="$1"

    # States are returned in chronological order
    # See: https://github.com/koalaman/shellcheck/wiki/SC2207
    local loginNames=()
    while IFS='' read -r line; do loginNames+=("$line"); done < <(jq -r '.[].user.login' <<< "${prStatus}")
    local reviewStates=()
    while IFS='' read -r line; do reviewStates+=("$line"); done < <(jq -r '.[].state' <<< "${prStatus}")

    local j
    j=0

    # Store all reviews
    while [ ${#loginNames[@]} -gt $j ]; do
        review_set "${loginNames[$j]}" "${reviewStates[$j]}"

        j=$((j+1))
    done

    
    local i=0
    while [ ${#loginNames[@]} -gt $i ]; do
        local loginName
        loginName="${loginNames[$i]}"

        local loginCount
        loginCount=$(login_get "$loginName")
        
        # shellcheck disable=SC2086
        if [ $loginCount -eq 0 ]; then

            login_set "$loginName"

            # Get the latest review
            local latestState
            latestState=$(review_get "$loginName")
            
            log "Debug: Latest state $latestState for $loginName"

            if [ "$latestState" == "$PR_CHANGES_REQUESTED" ];
            then 
                changesRequested=true
                break
            elif [ "$latestState" == "$PR_APPROVED" ]; 
            then
                approvalCount=$((approvalCount+1))
            fi
        fi

        i=$((i+1))
    done

    log "Debug: Approval count $approvalCount"
    
    # shellcheck disable=SC2086
    if [ "$changesRequested" == true ]; then
        log "Debug: Changes requested"
        echo false
    elif [ $approvalCount -ge $DEFAULT_APPROVAL_COUNT ]; then
        echo true
    else
        echo false
    fi

    review_flush
    login_flush
}

function updatePR {
    log "Function updatePR"

    local pr_num
    pr_num=$1

    local updateStatus
    # shellcheck disable=SC2086
    updateStatus=$(curl -s -X POST -u "$GIT_NAME":"$GIT_TOKEN" -H "Content-Type: application/json" "$GIT_MERGE_API" -d ' 
    {
        "base": '\"$PR_BRANCH\"',
        "head": '\"$BASE_BRANCH\"'
    }')

    local conflictCount
    conflictCount=$(grep -o -i 'Merge Conflict' <<< "$updateStatus" | wc -l)
    
    # shellcheck disable=SC2086
    if [ $conflictCount -eq 0 ];
    then
        echo true
    else
        log "$CONFLICT_STATUS $pr_num"
        echo false
    fi
}

function checkReadyToBuildOrMerge {
    log "Function checkReadyToBuild"

    local pr_num
    pr_num=$1

    local reviewDetails
    reviewDetails=$(getCall "$GIT_REVIEWS_API" "$pr_num")

    local isPRValid
    isPRValid=$(isPROpenAndUnmerged "$pr_num")
    local approved
    approved=$(isApproved "$reviewDetails")
    local isUpdateSuccessful
    isUpdateSuccessful=$(updatePR "$pr_num")

    if [ "$isPRValid" == true ] && [ "$approved" == true ] && [ "$isUpdateSuccessful" == true ];
    then
        log "PR $pr_num ready to build"
        echo true
    else
        log "PR $pr_num not ready to build"
        echo false
    fi
}

function triggerCommentBuild {
    log "Function triggerBuild"

    local pr_num
    pr_num=$1

    local commentsApi
    # shellcheck disable=SC2059
    commentsApi=$(printf "$GIT_ISSUES_COMMENTS_API" "$pr_num")

    curl -s -X POST -u "$GIT_NAME":"$GIT_TOKEN" -H "Content-Type: application/json" "$commentsApi" -d ' 
    {
        "body": "OK to test"
    }'

    log "Build triggered for $pr_num"
}

function triggerBuild {
    local pr_num
    pr_num=$1
    if [ "$COMMENT_BASED_BUILD" = true ]; then
        triggerCommentBuild "$pr_num"
    else
        echo "Build Script option yet to be implemented!"
        exit 1
    fi
}

function mergePR {
    log "Function mergePR"

    pr_num=$1

    local mergeApi
    # shellcheck disable=SC2059
    mergeApi=$(printf "$GIT_PR_MERGE_API" "$pr_num")
    local mergeStatus

    # Branches to release aren't squashed as it will ruin the commit history.
    if [ "$PR_BRANCH" == "release" ] || [ "$BASE_BRANCH" == "release" ] || [ "$DEFAULT_MERGE" == "merge" ]; then
        log "Doing default merge for prBranch: $PR_BRANCH & baseBranch: $BASE_BRANCH"
        mergeStatus=$(curl -s -X PUT -u "$GIT_NAME":"$GIT_TOKEN" "$mergeApi")
    else
        log "Doing squash merge for prBranch: $PR_BRANCH & baseBranch: $BASE_BRANCH"
        mergeStatus=$(curl -s -X PUT -u "$GIT_NAME":"$GIT_TOKEN" "$mergeApi" -d '{"merge_method": "squash"}')
    fi    

    
    echo "$mergeStatus"
}
