#!/bin/bash

S3_BUCKET_NAME=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
PROJECT_NAME=test
BRANCH_NAME=optimize-image-"$(date +"%Y%m%d%H%M%S")"
TARGET_BRANCH=master

REPO_NAME="$(echo $CODEBUILD_SOURCE_REPO_URL | sed "s/https:\/\/github\.com\/\(.*\)\.git/\1/")"
git remote set-url origin "https://${GITHUB_USERNAME}:${GITHUB_ACCESS_TOKEN}@github.com/${REPO_NAME}.git"

CURRENT_BRANCH="$(git branch | sed -e '/^[^*]/d' -e "s/* \(.*\)/\1/")"
LATEST_TARGET_REVISION="$(git rev-parse --short origin/${TARGET_BRANCH})"

PREV_REVISION="$(aws s3 cp s3://"$S3_BUCKET_NAME"/"$PROJECT_NAME"/latest_revision /latest_revision >/dev/null 2>&1 && cat /latest_revision || git rev-list --max-parents=0 HEAD)"

[ "$CURRENT_BRANCH" != "(HEAD detached at ${LATEST_TARGET_REVISION})" ] && exit

git config --global user.email "$GITHUB_EMAIL"
git config --global user.name "$GITHUB_USERNAME"

git checkout -b "$BRANCH_NAME"

JPG_LIST="$(git log --oneline --name-status --no-merges "$PREV_REVISION"..HEAD -- *.jpg | grep -E '^(A|M)[[:space:]].*' | awk '{ print $2 }' | uniq)"

for file in $JPG_LIST; do
    [ ! -f "$file" ] && continue
    cjpeg -progressive -quality 90 "$file" > tmp && mv tmp "$file"
done

PNG_LIST="$(git log --oneline --name-status --no-merges "$PREV_REVISION"..HEAD -- *.png | grep -E '^(A|M)[[:space:]].*' | awk '{ print $2 }' | uniq)"
for file in $PNG_LIST; do
    [ ! -f "$file" ] && continue
    zopfli -c "$file" > tmp && mv tmp "$file"
done

echo "$CODEBUILD_SOURCE_VERSION" > /latest_revision

git status 2> /dev/null | tail -n1 | grep 'working tree clean' && exit

git add .
git commit -m "Optimize images"
git push origin "$BRANCH_NAME"

curl \
    -H "Authorization: token ${GITHUB_ACCESS_TOKEN}" \
    -d "{ \"title\": \"Optimize Images\", \"head\": \"${BRANCH_NAME}\", \"base\": \"${TARGET_BRANCH}\" }" \
    https://api.github.com/repos/${REPO_NAME}/pulls
