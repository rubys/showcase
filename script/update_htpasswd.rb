#!/usr/bin/env ruby

# Update htpasswd file from index database
# This script is called as a hook by Navigator on server start and resume

require 'bundler/setup'
require_relative '../lib/htpasswd_updater'

HtpasswdUpdater.update
