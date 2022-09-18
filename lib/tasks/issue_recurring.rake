desc <<-END_DESC
Create pending recurrences for issues.

Example:
  RAILS_ENV=production rake redmine:issue_recurring:renew_all 
END_DESC

require_relative '../../../../config/environment'

namespace :redmine do
  namespace :issue_recurring do
    task :renew_all => :environment do
      IssueRecurrence.renew_all
    end
  end
end
