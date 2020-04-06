# Required for Puma to start in test env for system tests (RAILS_ENV=test does
# not work).
ENV["RACK_ENV"] = "test"

# Load the Redmine helper
require File.expand_path('../../../../test/application_system_test_case', __FILE__)
require File.expand_path('../test_case', __FILE__)

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

  Capybara.configure do |config|
    config.save_path = './tmp/screenshots/'
  end

  fixtures :issues, :issue_statuses,
    :users, :email_addresses, :trackers, :projects,
    :roles, :members, :member_roles, :enabled_modules, :workflow_transitions,
    :custom_fields, :enumerations

  include IssueRecurringTestCase
  include AbstractController::Translation
  include ActionView::Helpers::SanitizeHelper

  def logout_user
    click_link t(:label_logout)
    assert_current_path home_path
    assert_link t(:label_login)
  end

  def create_recurrence(issue=issues(:issue_01), **attributes)
    t_base = 'issues.recurrences.form'
    visit issue_path(issue)
    assert_difference 'all("#recurrences tr").length', 1 do
      within 'div#issue_recurrences' do
        click_link t(:button_add)
        attributes.each do |k, v|
          select strip_tags(t("#{t_base}.#{k.to_s.pluralize}.#{v}")), from: "recurrence_#{k}"
        end
        click_button t(:button_add)
      end
      assert_current_path issue_path(issue)
      assert_no_text '#recurrence-errors'
    end
    #attributes[:anchor_mode] ||= :first_issue_fixed
    #attributes[:mode] ||= :weekly
    #attributes[:multiplier] ||= 1
    #assert_difference 'IssueRecurrence.count', 1 do
    #  post "#{issue_recurrences_path(issue)}.js", params: {recurrence: attributes}
    #end
    #IssueRecurrence.last
  end
end
