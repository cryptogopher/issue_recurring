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
    super
    logout_user
  end

  def test_show_issue_recurrences
    visit issues_url(@issue1)
    #assert_selector "h1", text: "IssueRecurrence"
  end
end
