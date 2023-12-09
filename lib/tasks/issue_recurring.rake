desc <<-END_DESC
Create pending recurrences for issues.

Example:
  RAILS_ENV=production rake redmine:issue_recurring:renew_all 
END_DESC

require_relative '../../../../config/environment'

namespace :redmine do
  namespace :issue_recurring do
    task :renew_all => :environment do
      Mailer.with_synched_deliveries { IssueRecurrence.renew_all }
    end
  end

  namespace :plugins do
    namespace :test do
      desc 'Runs the plugins migration tests.'
      task :migration => "db:test:prepare" do |t|
        $: << "test"
        Rails::TestUnit::Runner.rake_run ["plugins/#{ENV['NAME'] || '*'}/test/migration/**/*_test.rb"]
      end
    end
  end
end
