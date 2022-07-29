# Required for Puma to start in test env for system tests (RAILS_ENV=test does
# not work).
ENV["RACK_ENV"] = "test"

# Load the Redmine helper
require File.expand_path('../../../../test/application_system_test_case', __FILE__)
require File.expand_path('../test_case', __FILE__)

class IssueRecurringSystemTestCase < ApplicationSystemTestCase
  driven_by :selenium, using: :headless_firefox, screen_size: [1280, 1024] do
    Selenium::WebDriver::Firefox::Options.new prefs: {
      'browser.download.dir' => DOWNLOADS_PATH,
      'browser.download.folderList' => 2,
      'browser.helperApps.neverAsk.saveToDisk' => 'application/pdf',
      'pdfjs.disabled' => true
    }
  end

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
    #attributes[:mode] ||= :weekly
    t_base = 'issues.recurrences.form'

    visit issue_path(issue)
    assert_difference ['all("#recurrences tr").length', 'IssueRecurrence.count'], 1 do
      within '#issue_recurrences' do
        click_link t(:button_add)
        attributes.each do |k, v|
          value = case k
                  when :mode
                    interval = t("#{t_base}.mode_intervals.#{v}")
                    description = t("#{t_base}.mode_descriptions.#{v}")
                    "#{interval}(s)" + (description.present? ? ", #{description}" : '')
                  when :anchor_to_start
                    t("#{t_base}.#{k.to_s}.#{v}")
                  else
                    t("#{t_base}.#{k.to_s.pluralize}.#{v}")
                  end
          select strip_tags(value), from: "recurrence_#{k}"
        end
        click_button t(:button_add)
      end
      # status_code not supported by Selenium
      assert_current_path issue_path(issue)
      assert_selector '#recurrence-errors', visible: :all, exact_text: ''
    end
    IssueRecurrence.last
  end

  def destroy_recurrence(recurrence)
    visit issue_path(recurrence.issue)

    assert_difference ['all("#recurrences tr").length', 'IssueRecurrence.count'], -1 do
      within "#recurrences tr[id=recurrence-#{recurrence.id}]" do
        click_link t(:button_delete)
      end
      # status_code not supported by Selenium
      assert_current_path issue_path(recurrence.issue)
      assert_selector '#recurrence-errors', visible: :all, exact_text: ''
    end
  end

  def close_issue(issue)
    assert !issue.closed?
    closed_on = issue.closed_on
    status = IssueStatus.all.where(is_closed: true).first

    visit edit_issue_path(issue)
    within 'form#issue-form' do
      select status.name, from: t(:field_status)
      click_button t(:button_submit)
    end
    issue.reload

    assert_equal status.id, issue.status_id
    assert_not_nil issue.closed_on
    assert_not_equal closed_on, issue.closed_on
    assert issue.closed?
  end
end
