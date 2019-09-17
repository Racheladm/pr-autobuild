#!/bin/bash

set -Eexo pipefail


# Git APIs
GIT_PR_API="https://api.github.com/repos/bidgely/pingpong/pulls/%s"
GIT_ISSUES_COMMENTS_API="https://api.github.com/repos/bidgely/pingpong/issues/%s/comments"
GIT_REVIEWS_API="https://api.github.com/repos/bidgely/pingpong/pulls/%s/reviews"
GIT_COMMENT_API="https://api.github.com/repos/bidgely/pingpong/pulls/%s/comments"

# Constants
# approval count is integer
DEFAULT_APPROVAL_COUNT=2
BASE_BRANCH=master
PR_APPROVED='APPROVED'
APPROVAL_TAG=
COMMENT_BASED_BUILD=true
BUILD_COMMENT="OK to test"


# Variables
BUILD_UPDATE_TIME=10

# PR Status
MERGED_STATUS='MERGED'
UNMERGED_STATUS='UNMERGED'
ALREADY_MERGED_STATUS='ALREADY_MERGED'
MERGE_FAILED_STATUS='MERGE_FAILED'
BUILD_FAILED_STATUS='BUILD_FAILED'
NOT_READY_STATUS='NOT_READY'
CONFLICT_STATUS='CONFLICT'


PR_STATE=()
PR_NUM=()