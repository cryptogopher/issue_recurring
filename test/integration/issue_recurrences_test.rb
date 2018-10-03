require File.expand_path('../../test_helper', __FILE__)

class IssueRecurrencesTest < Redmine::IntegrationTest
  fixtures :issues, :issue_statuses, :issue_priorities,
    :users, :email_addresses, :trackers, :projects, 
    :roles, :members, :member_roles, :enabled_modules, :workflow_transitions

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
    issue1 = renew_all(1).first
    assert_equal Date.new(2018,10,11), issue1.start_date
    assert_equal Date.new(2018,10,15), issue1.due_date
    travel(8.days)
    renew_all(0)
    travel(22.days)
    issue2, issue3, issue4 = renew_all(3)
    assert_equal Date.new(2018,10,21), issue2.start_date
    assert_equal Date.new(2018,10,25), issue2.due_date
    assert_equal Date.new(2018,10,31), issue3.start_date
    assert_equal Date.new(2018,11,4), issue3.due_date
    assert_equal Date.new(2018,11,10), issue4.start_date
    assert_equal Date.new(2018,11,14), issue4.due_date
  end
end
