require File.expand_path('../../application_system_test_case', __FILE__)

class IssueRecurrencesTest < IssueRecurringSystemTestCase
  def setup
    super

    Setting.non_working_week_days = [6, 7]
    Setting.plugin_issue_recurring['author_id'] = 0
    Setting.plugin_issue_recurring['keep_assignee'] = false
    Setting.plugin_issue_recurring['add_journal'] = false

    @issue1 = issues(:issue_01)
    @issue2 = issues(:issue_02)
    @issue3 = issues(:issue_03)

    log_user 'alice', 'foo'
  end

  def teardown
    logout_user
    super
  end

  def test_show_issue_recurrences
    visit issue_path(@issue1)
  end

  def test_settings_add_journal
    @issue1.update!(start_date: 10.days.ago, due_date: 5.days.ago)
    create_recurrence(creation_mode: :copy_first)
    logout_user

    log_user 'admin', 'foo'
    visit plugin_settings_path(id: 'issue_recurring')

    uncheck t('settings.issue_recurrences.add_journal')
    click_button t(:button_apply)
    assert_text '#flash_notice', t(:notice_successful_update)
    travel_to(@issue1.start_date)
    r1 = assert_no_difference 'Journal.count' do
      renew_all(1)
    end

    check t('settings.issue_recurrences.add_journal')
    click_button t(:button_apply)
    assert_text '#flash_notice', t(:notice_successful_update)
    travel_to(r1.start_date)
    assert_difference 'Journal.count', 1 do
      renew_all(1)
    end

    assert_equal @issue1.author, Journal.last.user
  end
end
