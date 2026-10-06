#!/usr/bin/env bash
# Build script run by Render before each deploy of the Rails API.
# Fail the build if any command fails.
set -o errexit

bundle install

# Notes:
#  - Mongoid is schema-less, so there are no ActiveRecord migrations to run.
#  - This is an API-only app, so there are no assets to precompile.
