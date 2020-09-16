# Find Inactive Organization Members

This is a forked version of [this script](https://github.com/github/platform-samples/blob/master/api/ruby/find-inactive-members/find_inactive_members.rb) for organizations that are looking to find inactive users and are running into rate limiting issues.

The script:
* prints all organization members into all_members.csv
* prints all repo names in a repositories.csv
* For the set of repositories we are analyzing, a csv will be generated of active users
* Once you're able to generate all active reports across all repositories, consolidate those into one list.
* Compare all_members list with the active users list from above. Users in the all_members list that aren't in the active_users list are considered inactive members


Steps
* Find the total number of repositories - this number will also be printed when you first run the script
* Limit each run to no more than 1500 repositories
* For example, if your organization 'get-secure' has 3500 repos, script invocation would be as such:
   * ```ruby find_inactive_members.rb -o myOrg -d "Aug 4 2020" -s 1 -f 1500  &```
   * ```ruby find_inactive_members.rb -o myOrg -d "Aug 4 2020" -s 1501 -f 2500  &```
   * ```ruby find_inactive_members.rb -o myOrg -d "Aug 4 2020" -s 2501 -f 3500  &```



```
find_inactive_members.rb - Find and output inactive members in an organization
    -d, --date MANDATORY             Date from which to start looking for activity (in a format parseable by the Ruby Date class: https://ruby-doc.org/stdlib/libdoc/date/rdoc/Date.html)
    -o, --organization MANDATORY     Organization to scan for inactive users
    -s, --start repository MANDATORY integer, defines start range of repositories to be analyzed
    -f, --finish repository MANDATORY integer, defines end range of repositories to be analyzed
    -c, --check                      Check connectivity and scope
    -e, --email                      Fetch the user email (can make the script take longer)
    -v, --verbose                    More output to STDERR
    -h, --help                       Display this help
```

## Installation

### Clone this repository

```shell
git clone https://github.com/github/platform-samples.git
cd platform-samples/api/ruby/find-inactive-members
```

### Install dependencies

```shell
gem install octokit
```

### Configure Octokit

The `OCTOKIT_ACCESS_TOKEN` is required in order to see activities on private repositories. Also note that GitHub.com has an rate limit of 60 unauthenticated requests per hour, which this tool can easily exceed. Access tokens can be generated at https://github.com/settings/tokens. The `OCTOKIT_API_ENDPOINT` isn't required if connecting to GitHub.com, but is required if connecting to a GitHub Enterprise instance.

```shell
export OCTOKIT_ACCESS_TOKEN=00000000000000000000000     # Required if looking for activity in private repositories.
export OCTOKIT_API_ENDPOINT="https://<your_github_enterprise_instance>/api/v3" # Not required if connecting to GitHub.com.
```

## Usage

```
ruby find_inactive_members.rb -o myOrg -d "Aug 4 2020" -s 1 -f 500  &    --> run in background, print to cli
nohup ruby find_inactive_members.rb -o myOrg -d "Aug 4 2020" -s 2 -f 3 > out.log 2>&1 &.  --> run in background, print to log file
```

## How Inactivity is Defined

Members are defined as inactive if they **have not performed** any of the following actions in any repository in the specified **ORGANIZATION** since the specified **DATE**: 

- Merged or pushed commits into the default branch
- Opened an Issue or Pull Request
- Commented on an Issue or Pull Request
