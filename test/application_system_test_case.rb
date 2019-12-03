# Required for Puma to start in test env
ENV["RACK_ENV"] = "test"

# Load the Redmine helper
require File.expand_path('../../../../test/application_system_test_case', __FILE__)
require File.expand_path('../fixture_loader', __FILE__)

class IssueRecurringSystemTestCase < ApplicationSystemTestCase
  profile = Selenium::WebDriver::Firefox::Profile.new
  profile['browser.download.dir'] = DOWNLOADS_PATH
  profile['browser.download.folderList'] = 2
  profile['browser.helperApps.neverAsk.saveToDisk'] = "application/pdf"
  profile['pdfjs.disabled'] = true
  #options = Selenium::WebDriver::Firefox::Options.new(profile: profile)

  driven_by :selenium, using: :headless_firefox, screen_size: [1280, 1024], options: {
    profile: profile
  }

  fixtures :issues, :issue_statuses,
    :users, :email_addresses, :trackers, :projects,
    :roles, :members, :member_roles, :enabled_modules, :workflow_transitions,
    :custom_fields, :enumerations

  class Date < ::Date
    def self.today
      # Due to its nature, Date.today may sometimes be equal to Date.yesterday/tomorrow.
      # https://rails.lighthouseapp.com/projects/8994-ruby-on-rails/tickets
      # /6410-dateyesterday-datetoday
      # For this reason WE SHOULD NOT USE Date.today anywhere in the code and use
      # Date.current instead.
      raise "Date.today should not be called!"
    end
  end

  def logout_user
    visit signout_path
    assert_equal '/logout', current_path
  end
end

