require File.expand_path('../../test_helper', __FILE__)

class IssueRecurrencesTest < Redmine::IntegrationTest
  fixtures :issues, :issue_statuses, :issue_priorities,
    :users, :email_addresses, :trackers, :projects, :journals, :journal_details

  def setup
    super
    @issue1 = issues(:issue_01)
  end

  def teardown
    super
    logout_user
  end

  def test_create_recurrence
    log_user 'alice', 'foo'
    create_recurrence
  end

  def test_renew_anchor_mode_first_issue_fixed_mode_daily
    log_user 'alice', 'foo'
    @issue1.start_date = Date.new(2018, 10, 1)
    @issue1.due_date = Date.new(2018, 10, 5)
    @issue1.save!
    travel_to(@issue1.start_date - 10.days)

    create_recurrence(anchor_mode: :first_issue_fixed, mode: :daily, multiplier: 10)
    renew_all(0)
    travel(9.days)
    renew_all(0)
    travel(1.day)
    puts Date.today
    renew_all(1)
    #Issue.find_by!(start_date: start_date, end_date: end_date)
  end
end
