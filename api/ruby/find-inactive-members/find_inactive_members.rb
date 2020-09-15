=begin

Inputs
-o organization
-d date in quotes for example "July 4 2020"
-s start row for repository
-f finish row for repository

example: ruby find_inactive_members.rb -o github -d "Aug 4 2020" -s 1 -f 30

The below script
* prints all organization members into all_members.csv
* prints all repo names in a repositories.csv
* For the set of repositories we are analyzing, a csv will be generated of active users
* Once you're able to generate all active reports across all repositories, you can consolidate those into one list with unique users.
* Compare all_members list from active users from above to find inactive members


Script Logic
 1. Loops through all organization_members
 2. Loops through all organization_repositories
 3. member_activity - loops through each repo, returns actions since specified date, and marks members as active 
 4. member_activity - open CSV, print inactive users

Runtime: total # of members (N) * total # of repo(N) * member actions (1) = N^2

Instead of N^2 runtime, we'll reduce this to N by by making repositories we access static to a certain number

Ideas
* Option 1: We can look to print repositories in a CSV, and run this script on a subset of repos. Each printed csv would give
us inactive users for that group of repos - inactive users across all groups are truly inactive across the organization
* Option 2: We can look to print member information in a CSV, and run this script on a subset of members. Each printed csv would give
us inactive users for that group of users

Other Ideas:
* We can use GET /rate_limit (documented here: https://developer.github.com/v3/rate_limit/) to sleep when needed, and restart the script using the returned reset (The time at which the current rate limit window resets in UTC epoch seconds)
* We can limit the number of events we check against (comment out lines 270-273)
* Run as a background job

Implemention Design
* Print all repositories to a csv doc
* Use csv doc as input for script
  * For example, ruby find_inactive_members.rb 1 30 -o github -d "Aug 4 2020" should find active users since the date for the first 30 repos
  * For example, ruby find_inactive_members.rb 31 60 -o github -d "Aug 4 2020" should find active users since the date for the 31st to 60th repos
* Print active users for that subset of repositories
  * Make the name of the outputted file dynamic so it's not over written
* At the end, merge all active lists into one unique list - compare that with the all_members.csv to find inactive users

=end

require "csv"
require "octokit"
require 'optparse'
require 'optparse/date'

class InactiveMemberSearch
  attr_accessor :organization, :members, :repositories, :date, :unrecognized_authors, :group

  SCOPES=["read:org", "read:user", "repo", "user:email"]

  def initialize(options={})
    @client = options[:client]
    if options[:check]
      check_app
      check_scopes
      check_rate_limit
      exit 0
    end

    raise(OptionParser::MissingArgument) if (
      options[:organization].nil? or
      options[:date].nil?
      options[:start].nil?
      options[:finish].nil?
    )

    @date = options[:date]
    @organization = options[:organization]
    @email = options[:email]
    @unrecognized_authors = []
    @start_row = options[:start].to_i - 1
    @finish_row = options[:finish].to_i - 1

    organization_members
    organization_repositories
    member_activity
  end

  def check_app
    info "Application client/secret? #{@client.application_authenticated?}\n"
    info "Authentication Token? #{@client.token_authenticated?}\n"
  end

  def check_scopes
    info "Scopes: #{@client.scopes.join ','}\n"
  end

  def check_rate_limit
    info "Rate limit: #{@client.rate_limit.remaining}/#{@client.rate_limit.limit}\n"
  end

  def env_help
    output=<<-EOM
  Required Environment variables:
    OCTOKIT_ACCESS_TOKEN: A valid personal access token with Organzation admin priviliges
    OCTOKIT_API_ENDPOINT: A valid GitHub/GitHub Enterprise API endpoint URL (Defaults to https://api.github.com)
  EOM
    output
  end

  # helper to get an auth token for the OAuth application and a user
  def get_auth_token(login, password, otp)
    temp_client = Octokit::Client.new(login: login, password: password)
    res = temp_client.create_authorization(
      {
        :idempotent => true,
        :scopes => SCOPES,
        :headers => {'X-GitHub-OTP' => otp}
      })
    res[:token]
  end
private
  def debug(message)
    $stderr.print message
  end

  def info(message)
    $stdout.print message
  end

  def member_email(login)
    @email ? @client.user(login)[:email] : ""
  end

  def organization_members
  # get all organization members and place into an array of hashes
    info "Finding #{@organization} members "
    @members = @client.organization_members(@organization).collect do |m|
      email =
      {
        login: m["login"],
        email: member_email(m[:login]),
        active: false
      }
    end
    info "#{@members.length} members found.\n"
   

    CSV.open("all_members.csv", "wb") do |csv|
      csv << ["login", "email"]
      # iterate and print inactive members
      @members.each do |member|
        member_detail = []
        member_detail << member[:login]
        member_detail << member[:email] unless member[:email].nil?
        csv << member_detail
        # info "#{member_detail} is saved\n"
      end
      info "Members saved in csv format"
    end
   
  end

  def organization_repositories
    info "\n Gathering a list of repositories..."
    # get all repos in the organizaton and place into a hash
    @repositories = @client.organization_repositories(@organization).collect do |repo|
      repo["full_name"]
    end
    info "#{@repositories.length} repositories discovered\n"


    CSV.open("repositories.csv", "wb") do |csv|
      csv << ["repositories"]
      # iterate and print inactive members
      @repositories.each do |repo|
        repo_detail = []
        repo_detail << repo
        csv << repo_detail
      end 
    end

    info "\n Repos saved in csv format"

  end

  def add_unrecognized_author(author)
    @unrecognized_authors << author
  end

  # method to switch member status to active
  def make_active(login)
    hsh = @members.find { |member| member[:login] == login }
    hsh[:active] = true
  end

  def commit_activity(repo)
    # get all commits after specified date and iterate
    info "\n...commits"
    begin
      @client.commits_since(repo, @date).each do |commit|
        # if commmitter is a member of the org and not active, make active
        if commit["author"].nil?
          add_unrecognized_author(commit[:commit][:author])
          next
        end
        if t = @members.find {|member| member[:login] == commit["author"]["login"] && member[:active] == false }
          make_active(t[:login])
        end
      end
    rescue Octokit::Conflict
      info "...no commits"
    rescue Octokit::NotFound
      #API responds with a 404 (instead of an empty set) when the `commits_since` range is out of bounds of commits.
      info "...no commits"
    end
  end

  def issue_activity(repo, date=@date)
    # get all issues after specified date and iterate
    info "\n...Issues"
    begin
      @client.list_issues(repo, { :since => date }).each do |issue|
        # if there's no user (ghost user?) then skip this   // THIS NEEDS BETTER VALIDATION
        if issue["user"].nil?
          next
        end
        # if creator is a member of the org and not active, make active
        if t = @members.find {|member| member[:login] == issue["user"]["login"] && member[:active] == false }
          make_active(t[:login])
        end
      end
    rescue Octokit::NotFound
      #API responds with a 404 (instead of an empty set) when repo is a private fork for security advisories
      info "...no access to issues in this repo ..."
    end
  end

  def issue_comment_activity(repo, date=@date)
    # get all issue comments after specified date and iterate
    info "\n...Issue comments"
    begin
      @client.issues_comments(repo, { :since => date }).each do |comment|
        # if there's no user (ghost user?) then skip this   // THIS NEEDS BETTER VALIDATION
        if comment["user"].nil?
          next
        end
        # if commenter is a member of the org and not active, make active
        if t = @members.find {|member| member[:login] == comment["user"]["login"] && member[:active] == false }
          make_active(t[:login])
        end
      end
    rescue Octokit::NotFound
      #API responds with a 404 (instead of an empty set) when repo is a private fork for security advisories
      info "...no access to issue comments in this repo ..."
    end
  end

  def pr_activity(repo, date=@date)
    # get all pull request comments comments after specified date and iterate
    info "\n...Pull Request comments"
    @client.pull_requests_comments(repo, { :since => date }).each do |comment|
      # if there's no user (ghost user?) then skip this   // THIS NEEDS BETTER VALIDATION
      if comment["user"].nil?
        next
      end
      # if commenter is a member of the org and not active, make active
      if t = @members.find {|member| member[:login] == comment["user"]["login"] && member[:active] == false }
        make_active(t[:login])
      end
    end
  end

 def member_activity
    @repos_completed = 0
    # print update to terminal

    # scope repositories to static number based on inputted arguments
    @grouped_repositories = @repositories[@start_row..@finish_row]

    info "\n Analyzing activity for #{@members.length} members and #{@grouped_repositories.length} repos for #{@organization}\n"

    info "\n first repo to be analyzed: #{@grouped_repositories[@start_row]}"
    info "\n last repo to be analyzed: #{@grouped_repositories[@finish_row]}"
    # for each repo
    @grouped_repositories.each do |repo|
      info "rate limit remaining: #{@client.rate_limit.remaining}  "
      info "analyzing #{repo}"

      commit_activity(repo)
      issue_activity(repo)
      issue_comment_activity(repo)
      pr_activity(repo)

      # print update to terminal
      @repos_completed += 1
      info "...#{@repos_completed}/#{@grouped_repositories.length} repos completed\n"
    end

    filename = "active_users_for_repos-#{@start_row}-to-#{@finish_row}.csv"
    # open a new csv for output
    CSV.open(filename, "wb") do |csv|
      csv << ["login", "email"]
      # iterate and print inactive members
      @members.each do |member|
        if member[:active] == true
          member_detail = []
          member_detail << member[:login]
          member_detail << member[:email] unless member[:email].nil?
          info "#{member_detail} is active\n in the repositories we've accessed"
          csv << member_detail
        end
      end
    end

    CSV.open("unrecognized_authors.csv", "wb") do |csv|
      csv << ["name", "email"]
      @unrecognized_authors.each do |author|
        author_detail = []
        author_detail << author[:name]
        author_detail << author[:email]
        info "#{author_detail} is unrecognized\n"
        csv << author_detail
      end
    end
  end
end

options = {}
OptionParser.new do |opts|
  opts.banner = "#{$0} - Find and output inactive members in an organization"

  opts.on('-c', '--check', "Check connectivity and scope") do |c|
    options[:check] = c
  end

  opts.on('-d', '--date MANDATORY',Date, "Date from which to start looking for activity") do |d|
    options[:date] = d.to_s
  end

  opts.on('-e', '--email', "Fetch the user email (can make the script take longer") do |e|
    options[:email] = e
  end

  opts.on('-o', '--organization MANDATORY',String, "Organization to scan for inactive users") do |o|
    options[:organization] = o
  end

  opts.on('-s', '--start MANDATORY',String, "csv start column") do |s|
    options[:start] = s
  end

  opts.on('-f', '--finish MANDATORY',String, "csv end column") do |f|
    options[:finish] = f
  end

  opts.on('-v', '--verbose', "More output to STDERR") do |v|
    @debug = true
    options[:verbose] = v
  end

  opts.on('-h', '--help', "Display this help") do |h|
    puts opts
    exit 0
  end
end.parse!

stack = Faraday::RackBuilder.new do |builder|
  builder.use Octokit::Middleware::FollowRedirects
  builder.use Octokit::Response::RaiseError
  builder.use Octokit::Response::FeedParser
  builder.response :logger
  builder.adapter Faraday.default_adapter
end

Octokit.configure do |kit|
  kit.auto_paginate = true
  kit.middleware = stack if @debug
end

options[:client] = Octokit::Client.new

InactiveMemberSearch.new(options)
