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

  def random_datespan
    rand([0..7, 8..31, 32..3650].sample)
  end

  def random_date
    Date.current + random_datespan * [-1, 1].sample
  end

  def random_dates
    dates = {start_date: random_date}
    dates.update(due_date: dates[:start_date] + random_datespan)
  end

  def random_recurrence
    r = {
      creation_mode: IssueRecurrence.creation_modes.keys.sample.to_sym,
      include_subtasks: [true, false].sample,
      multiplier: rand([1..4, 5..100, 101..1000].sample),
      mode: IssueRecurrence.modes.keys.sample.to_sym,
      anchor_to_start: [true, false].sample
    }

    disallowed = (r[:creation_mode] == :reopen) ? [:first_issue_fixed, :last_issue_fixed] : []
    r[:anchor_mode] = (IssueRecurrence.anchor_modes.keys.map(&:to_sym) - disallowed).sample

    r[:anchor_date] = random_date if r[:anchor_mode] == :date_fixed_after_close

    unless IssueRecurrence::FLEXIBLE_ANCHORS.map(&:to_sym).include? r[:anchor_mode]
      r[:delay_multiplier] = rand([0..0, 1..366].sample)
      r[:delay_mode] = IssueRecurrence.delay_modes.keys.sample.to_sym
    end

    case rand(1..4)
    when 1
      r[:date_limit] = Date.current + rand([1..31, 32..3650].sample).days
    when 2
      r[:count_limit] = rand([0..12, 13..1000].sample)
    else
      # 50% times do not set the limit
    end

    r
  end

  def within_issue_recurrences_panel
    panel_label = t('issues.issue_recurrences_hook.recurrences')
    within :xpath, "//div[p[contains(string(), '#{panel_label}')]]" do
      yield
    end
  end

  def create_recurrence(issue: issues(:issue_01), **attributes)
    t_base = 'issues.recurrences.form'
    recurrence = nil

    attributes[:anchor_mode] ||= :first_issue_fixed
    attributes[:mode] ||= :weekly
    attributes[:multiplier] ||= 1

    visit issue_path(issue)
    within_issue_recurrences_panel do
      assert_difference ['all("tr").length', 'IssueRecurrence.count'], 1 do
        click_link t(:button_add)
        attributes.each do |k, v|
          helper_method = "#{k}_options".to_sym
          if respond_to?(helper_method)
            v = send(helper_method).to_h { |v,k| [k,v] }[v]
            select strip_tags(v), from: "recurrence_#{k}"
          else
            fill_in "recurrence_#{k}", with: v
          end
        end
        click_button t(:button_submit)
      end

      recurrence = IssueRecurrence.last
      # status_code not supported by Selenium
      assert_current_path issue_path(issue)
      assert_selector :xpath,
        "//tr[td[contains(string(), '#{strip_tags(recurrence.to_s)}')]]"
      assert_no_selector '#new-recurrence *', visible: :all
    end
    assert_selector 'div#flash_notice', exact_text: t('issue_recurrences.create.success')

    attributes.each do |attribute, value|
      value = value.to_s if value.is_a? Symbol
      assert_equal value, recurrence.send(attribute)
    end

    recurrence
  end

  def update_recurrence(recurrence, **attributes, &block)
    t_base = 'issues.recurrences.form'
    attributes.stringify_keys!

    visit issue_path(recurrence.issue)
    within_issue_recurrences_panel do
      assert_changes 'recurrence.attributes' do
        within :xpath, "//tr[td[contains(string(), '#{strip_tags(recurrence.to_s)}')]]" do
          click_link t(:button_edit)
        end

        attributes.each do |k, v|
          helper_method = "#{k}_options".to_sym
          if respond_to?(helper_method)
            v = send(helper_method).to_h { |v,k| [k,v] }[v]
            select strip_tags(v), from: "recurrence_#{k}"
          else
            fill_in "recurrence_#{k}", with: v
          end
        end

        yield

        click_button t(:button_submit)
        recurrence.reload

        # status_code not supported by Selenium
        assert_current_path issue_path(recurrence.issue)
        assert_no_selector '#new-recurrence *', visible: :all
        assert_selector :xpath,
          "//tr[td[contains(string(), '#{strip_tags(recurrence.to_s)}')]]"
        assert_equal attributes, recurrence.attributes.extract!(*attributes.keys)
      end
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
