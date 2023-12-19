# Required for Puma to start in test env for system tests (RAILS_ENV=test does
# not work).
ENV["RACK_ENV"] = "test"

# NOTE: remove following 2 requires when Rails < 6 no longer supported and
# autoloading properly loads classes in 'prepend' below
require 'action_dispatch'
require_relative '../lib/issue_recurring/system_test_case_patch'
# Avoid preloading Chrome, which is used by Redmine
ActionDispatch::SystemTestCase.singleton_class.prepend IssueRecurring::SystemTestCasePatch

# Load the Redmine helper
require_relative '../../../test/application_system_test_case'
require_relative 'test_case'

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
    config.default_max_wait_time = 0
  end

  self.fixture_path = File.expand_path('../fixtures/', __FILE__)
  fixtures :issues, :issue_statuses,
    :users, :email_addresses, :trackers, :projects,
    :roles, :members, :member_roles, :enabled_modules, :workflow_transitions,
    :custom_fields, :enumerations

  include IssueRecurringTestCase
  include AbstractController::Translation
  include ActionView::Helpers::SanitizeHelper
  include IssueRecurring::IssuesHelperPatch

  def logout_user
    click_link t(:label_logout)
    assert_current_path home_path
    assert_link t(:label_login)
  end

  def within_issue_recurrences_panel
    panel_label = t('issues.issue_recurrences_hook.recurrences')
    within :xpath, "//div[p[contains(string(), '#{panel_label}')]]" do
      yield
    end
  end

  def fill_in_form(attributes)
    helper_attrs = {}
    attributes.keys.grep(/_limit$/) { |k| helper_attrs[:limit_mode] = k.to_sym }

    field = first(:field)
    begin
      id = field[:id].delete_prefix('recurrence_').to_sym
      if key = (attributes[id] || helper_attrs[id])
        if field.tag_name == 'select'
          helper_method = "#{id}_options".to_sym
          value = send(helper_method).to_h.invert[key]
          field.select value
        else
          field.fill_in with: key
        end
      end
      field = field.find(:xpath, 'following-sibling::*[self::input or self::select]',
                         match: :first)
    rescue Capybara::ElementNotFound
      break
    end while true
  end

  def fill_in_randomly
    all('select', visible: :all).each { |s| s.all('option').sample&.select_option }
    all('input[type=number]').each do |i|
      min = i[:min].to_i || 0
      i.fill_in with: rand([min..min, (min+1)..5, 6..1000].sample)
    end
    all('input[type=date]', visible: :all).each { |i| i.fill_in with: random_future_date }
  end

  # Create recurrence by filling out the form with:
  # * attributes, filled with missing required keys if necessary,
  # * block,
  # or randomly generated attributes when no attributes or block given.
  def create_recurrence(issue: issues(:issue_01), **attributes)
    t_base = 'issues.recurrences.form'
    recurrence = nil

    if attributes.empty?
      attributes = random_recurrence(issue) unless block_given?
    else
      attributes[:anchor_mode] ||= :first_issue_fixed
      attributes[:mode] ||= :weekly
      attributes[:multiplier] ||= 1
    end

    visit issue_path(issue)
    within_issue_recurrences_panel do
      assert_difference ['all("tr").length', 'IssueRecurrence.count'], 1 do
        click_link t(:button_add)

        fill_in_form attributes
        yield if block_given?

        click_button t(:button_submit)
      end

      recurrence = IssueRecurrence.last
      # status_code not supported by Selenium
      assert_current_path issue_path(issue)
      assert_selector :xpath,
        "//tr[td[contains(string(), '#{strip_tags(recurrence.to_s)}')]]"
      assert_no_selector '#new-recurrence *', visible: :all
      attributes = attributes.map { |k,v| [k.to_s, v.is_a?(Symbol) ? v.to_s : v] }.to_h
      assert_equal attributes, recurrence.attributes.extract!(*attributes.keys)
    end
    assert_selector 'div#flash_notice', exact_text: t('issue_recurrences.create.success')

    recurrence
  end

  def update_recurrence(recurrence, **attributes)
    t_base = 'issues.recurrences.form'

    if attributes.empty? && !block_given?
      attributes = random_recurrence(recurrence.issue)
    end

    visit issue_path(recurrence.issue)
    within_issue_recurrences_panel do
      assert_no_difference ['all("tr").length', 'IssueRecurrence.count'] do
        within :xpath, "//tr[td[contains(string(), '#{strip_tags(recurrence.to_s)}')]]" do
          click_link t(:button_edit)
        end

        fill_in_form attributes
        yield if block_given?

        click_button t(:button_submit)
      end

      recurrence.reload
      # status_code not supported by Selenium
      assert_current_path issue_path(recurrence.issue)
      assert_selector :xpath,
        "//tr[td[contains(string(), '#{strip_tags(recurrence.to_s)}')]]"
      assert_no_selector '#new-recurrence *', visible: :all
      attributes = attributes.map { |k,v| [k.to_s, v.is_a?(Symbol) ? v.to_s : v] }.to_h
      assert_equal attributes, recurrence.attributes.extract!(*attributes.keys)
    end
    assert_selector 'div#flash_notice', exact_text: t('issue_recurrences.update.success')

    recurrence
  end

  def destroy_recurrence(recurrence)
    visit issue_path(recurrence.issue)

    within_issue_recurrences_panel do
      assert_difference ['all("tr").length', 'IssueRecurrence.count'], -1 do
        description = strip_tags(recurrence.to_s)
        within :xpath, "//tr[td[contains(string(), '#{description}')]]" do
          click_link t(:button_delete)
        end

        # status_code not supported by Selenium
        assert_current_path issue_path(recurrence.issue)
        assert_no_selector :xpath, "//tr[td[contains(string(), '#{description}')]]"
        assert_raises(ActiveRecord::RecordNotFound) { recurrence.reload }
      end
    end
    assert_selector 'div#flash_notice', exact_text: t('issue_recurrences.destroy.success')
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
