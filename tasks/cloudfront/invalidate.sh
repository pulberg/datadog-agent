#!/bin/bash
set -e

OPTIONS=""

if [ -n "$PATTERN_REGEX" ]
then
    OPTIONS="$OPTIONS --pattern-regex ${PATTERN_REGEX}"
fi

if [ -n "$PATTERN_SUBSTRING" ]
then
    OPTIONS="$OPTIONS --pattern-substring ${PATTERN_SUBSTRING}"
fi

if [ "$INVALIDATE_VERSIONED" = true ]
then
    OPTIONS="$OPTIONS --invalidate-versioned"
fi

if [ -n "$RAW_CLOUDFRONT_PATH" ]
then
    OPTIONS="$OPTIONS --raw-cloudfront-path ${RAW_CLOUDFRONT_PATH}"
fi

if [ "$DRY_RUN" = true ]
then
    OPTIONS="$OPTIONS --dry-run"
fi

# Invalidate CloudFront Edge cache
gem install bundler
bundle install
echo "Starting invalidation of $REPO repo"
bundle exec ./invalidate.rb --repo-type $REPO --env $ENV $OPTIONS
cd $WORKSPACE
