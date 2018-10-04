require File.expand_path('../../test_helper', __FILE__)

class IssueRecurrencesTest < Redmine::IntegrationTest
  fixtures :issues, :issue_statuses, :issue_priorities,
    :users, :email_addresses, :trackers, :projects, 
    :roles, :members, :member_roles, :enabled_modules, :workflow_transitions

  # Due to its nature, Date.today may sometimes be equal to Date.yesterday/tomorrow.
  # https://rails.lighthouseapp.com/projects/8994-ruby-on-rails/tickets
  # /6410-dateyesterday-datetoday
  # For this reason WE SHOULD NOT USE Date.today anywhere in the code and use
  # Date.current instead.
  class Date < ::Date
    def self.today
      raise "Date.today should not be called!"
    end
  end

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
    @issue1.start_date = Date.new(2018, 10, 1)
    @issue1.save!
    create_recurrence
  end

  def test_renew_anchor_mode_first_issue_fixed_mode_daily
    log_user 'alice', 'foo'
    @issue1.start_date = Date.new(2018, 10, 1)
    @issue1.due_date = Date.new(2018, 10, 5)
    @issue1.save!
    travel_to(@issue1.start_date - 10.days)

    create_recurrence(anchor_mode: :first_issue_fixed,
                      mode: :daily,
                      multiplier: 10)
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

  def test_renew_anchor_mode_first_issue_fixed_mode_weekly
    log_user 'alice', 'foo'
    @issue1.start_date = Date.new(2018, 8, 12)
    @issue1.due_date = Date.new(2018, 8, 20)
    @issue1.save!
    travel_to(@issue1.start_date - 2.weeks)

    create_recurrence(anchor_mode: :first_issue_fixed,
                      mode: :weekly,
                      multiplier: 4)
    renew_all(0)
    travel(2.weeks)
    issue1 = renew_all(1).first
    assert_equal Date.new(2018,9,9), issue1.start_date
    assert_equal Date.new(2018,9,17), issue1.due_date
    travel(27.days)
    renew_all(0)
    travel(1.month)
    issue2, issue3 = renew_all(2)
    assert_equal Date.new(2018,10,7), issue2.start_date
    assert_equal Date.new(2018,10,15), issue2.due_date
    assert_equal Date.new(2018,11,4), issue3.start_date
    assert_equal Date.new(2018,11,12), issue3.due_date
  end

  def test_renew_anchor_mode_first_issue_fixed_mode_monthly_day_from_first
    log_user 'alice', 'foo'
    @issue1.start_date = Date.new(2018, 9, 8)
    @issue1.due_date = Date.new(2018, 10, 2)
    @issue1.save!
    travel_to(@issue1.start_date - 1.year)

    create_recurrence(anchor_mode: :first_issue_fixed,
                      mode: :monthly_day_from_first,
                      multiplier: 2)
    renew_all(0)
    travel(4.months)
    renew_all(0)
    travel(8.months)
    issue1 = renew_all(1).first
    assert_equal Date.new(2018,11,8), issue1.start_date
    assert_equal Date.new(2018,12,2), issue1.due_date
    travel(1.month+30.days)
    renew_all(0)
    travel(3.months+28.days)
    issue2, issue3 = renew_all(2)
    assert_equal Date.new(2019,1,8), issue2.start_date
    assert_equal Date.new(2019,2,2), issue2.due_date
    assert_equal Date.new(2019,3,8), issue3.start_date
    assert_equal Date.new(2019,4,2), issue3.due_date
    travel(1.day)
    renew_all(1)
  end

  def test_renew_anchor_mode_first_issue_fixed_mode_monthly_day_to_last
    log_user 'alice', 'foo'
    @issue1.start_date = Date.new(2018, 9, 22)
    @issue1.due_date = Date.new(2018, 10, 10)
    @issue1.save!
    travel_to(@issue1.start_date - 6.months)

    create_recurrence(anchor_mode: :first_issue_fixed,
                      mode: :monthly_day_to_last,
                      multiplier: 3)
    renew_all(0)
    travel(2.months)
    renew_all(0)
    # Additional day due to: https://github.com/rails/rails/issues/34082 (DST change)
    travel(4.months+1.day)
    issue1 = renew_all(1).first
    assert_equal Date.new(2018,12,23), issue1.start_date
    assert_equal Date.new(2019,1,10), issue1.due_date
    travel(2.months+29.days)
    renew_all(0)
    travel(5.months+31.days)
    issue2, issue3 = renew_all(2)
    assert_equal Date.new(2019,3,23), issue2.start_date
    assert_equal Date.new(2019,4,9), issue2.due_date
    assert_equal Date.new(2019,6,22), issue3.start_date
    assert_equal Date.new(2019,7,10), issue3.due_date
    travel(1.day)
    renew_all(1)
  end

#  def test_travel
#    # this works
#    travel_to(Date.new(2018, 5, 1))
#
#    start = Date.current
#    travel_to(Date.current - 1.month)
#    travel(1.month)
#    assert_equal start, Date.current
#
#    # this doesn't work
#    travel_to(Date.new(2018, 4, 1))
#
#    start = Date.current
#    travel_to(Date.current - 1.month)
#    travel(1.month)
#    assert_equal start, Date.current
#  end

  def test_renew_anchor_mode_first_issue_fixed_mode_monthly_dow_from_first
    log_user 'alice', 'foo'
    @issue1.start_date = Date.new(2018, 9, 22)
    @issue1.due_date = Date.new(2018, 10, 10)
    @issue1.save!
    travel_to(@issue1.start_date - 6.months)

    create_recurrence(anchor_mode: :first_issue_fixed,
                      mode: :monthly_dow_from_first,
                      multiplier: 2)
    renew_all(0)
    travel(2.months)
    renew_all(0)
    # DST change
    travel(4.months+1.day)
    issue1 = renew_all(1).first
    assert_equal Date.new(2018,11,24), issue1.start_date
    assert_equal Date.new(2018,12,12), issue1.due_date
    # DST change
    travel(2.months-1.day)
    renew_all(0)
    travel(4.months)
    issue2, issue3 = renew_all(2)
    assert_equal Date.new(2019,1,26), issue2.start_date
    assert_equal Date.new(2019,2,13), issue2.due_date
    assert_equal Date.new(2019,3,23), issue3.start_date
    assert_equal Date.new(2019,4,10), issue3.due_date
    travel(1.day)
    renew_all(1)
  end

  # TODO:
  # - timespan much larger than recurrence period
  # - first_issue_fixed with date movement forward/backward
  # - first_issue_fixed with date > 28 recurring through February
  # - monthly_dow with same dow (2nd Tuesday+2nd Thursday) + month when 1st
  # Thursday is before 1st Tuesaday (start date ater than end date)
  # - monthly_dow when there is 5th day of week in one month but not in
  # subsequent
end

