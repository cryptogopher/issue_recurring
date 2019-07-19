# Required for Puma to start in test env
ENV["RACK_ENV"] = "test"
# FIXME: Check Rails version and exit if system tests not supported

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

  def logout_user
    visit signout_path
    assert_equal '/logout', current_path
  end
end

