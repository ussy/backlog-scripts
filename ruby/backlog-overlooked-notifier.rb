#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require "xmlrpc/client"
require "net/https"
require "openssl"
require "date"
require "pit"
require "optparse"

EXPIRES_DAY = 3
BUG = "バグ"
MESSAGE = "こちら確認して頂けましたでしょうか？"

class BacklogOverlookedNotifier
  def initialize(config, options)
    @config = config
    @options = options
    @client = XMLRPC::Client.new(config["space_url"], "/XML-RPC", 443, nil, nil, config["user"], config["password"], true, nil)
  end

  def get_user
    @client.call("backlog.getUser", @config["user"])
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
    if comments.empty?
      created_on = DateTime::strptime("#{issue['created_on']}#{@now.zone}", "%Y%m%d%H%M%S%Z")
      return EXPIRES_DAY <= (@now - created_on).to_i
    end

    targets = comments.select { |comment|
      created_on = DateTime::strptime("#{comment['created_on']}#{@now.zone}", "%Y%m%d%H%M%S%Z")

      comment["created_user"]["id"] != issue["created_user"]["id"] &&
      comment["created_user"]["id"] != @user["id"] ||
      (@now - created_on).to_i < EXPIRES_DAY
    }

    targets.empty?
  end

  def post_comment(issue)
    unless @options[:dryrun]
      @client.call("backlog.addComment", {
          :key => issue["key"],
          :content => MESSAGE
        })
    end
    puts "commented to #{issue['url']}"
  end

  def execute(project_keys)
    @now = DateTime.now
    @user = get_user
    project_keys.each { |name|
      issues = find_issues(name)
      issues.each { |issue|
        next unless overlooked_issue?(issue)
        post_comment(issue)

        sleep(1)
      }
    }
  end
end

options = {}
opts = OptionParser.new("Usage: backlog-overlooked-notifier [options] project_key project_key ...") do |opt|
  opt.on("-n", "--dry-run", "perform a trial run with no post comment") { |val| options[:dryrun] = val }
  opt.parse!(ARGV)
end

config = Pit.get("backlog", :require => {
    "space_url" => "your space url in backlog. ex) demo.backlog.jp",
    "user" => "your name in backlog. ex) demo",
    "password" => "your password in backlog. ex) demo"
  })

BacklogOverlookedNotifier.new(config, options).execute(ARGV)
