#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require "xmlrpc/client"
require "net/https"
require "openssl"
require "date"

SPACE = "please input space key"
USER = "please input user id"
PASS = "please input user password"
PROJECT_KEYS = ["please input project key"]
EXPIRES_DAY = 3
BUG = "バグ"
MESSAGE = "こちら確認して頂けましたでしょうか？"

class BacklogOverlookedNotifier
  def initialize
    @client = XMLRPC::Client.new(SPACE, "/XML-RPC", 443, nil, nil, USER, PASS, true, nil)
  end

  def get_project_keys
    PROJECT_KEYS
  end

  def get_user
    @client.call("backlog.getUser", USER)
  end

  def find_issues(project_name)
    project = @client.call("backlog.getProject", project_name)
    return [] if project.empty?

    @client.call("backlog.findIssue", {
        :projectId => project["id"],
        :issueType => BUG,
        :statusId => 1
      })
  end

  def overlooked_issue?(issue)
    comments = @client.call("backlog.getComments", issue["id"])
    return true if comments.empty?

    targets = comments.select { |comment|
      created_on = DateTime::strptime("#{comment['created_on']}#{@now.zone}", "%Y%m%d%H%M%S%Z")

      comment["created_user"]["id"] != issue["created_user"]["id"] &&
      comment["created_user"]["id"] != @user["id"] ||
      (@now - created_on).to_i < EXPIRES_DAY
    }
    return targets.empty?
  end

  def post_comment(issue)
    @client.call("backlog.addComment", {
        :key => issue["key"],
        :content => MESSAGE
      })
    puts "commented to #{issue['key']}"
  end

  def execute
    @now = DateTime.now
    @user = get_user
    project_keys = get_project_keys
    project_keys.each { |name|
      issues = find_issues(name)
      next if issues.empty?

      issues.each { |issue|
        next unless overlooked_issue?(issue)
        post_comment(issue)
      }
    }
  end
end

BacklogOverlookedNotifier.new.execute
