require File.expand_path('../../test_helper', __FILE__)

class IssueRecurrencesTest < Redmine::IntegrationTest
  fixtures :issues, :issue_statuses, :issue_priorities,
    :users, :email_addresses, :trackers, :projects, 
    :roles, :members, :member_roles, :enabled_modules, :workflow_transitions

  class Date < ::Date
    def self.today
      # Due to its nature, Date.today may sometimes be equal to Date.yesterday/tomorrow.
      # https://rails.lighthouseapp.com/projects/8994-ruby-on-rails/tickets
      # /6410-dateyesterday-datetoday
      # For this reason WE SHOULD NOT USE Date.today anywhere in the code and use
      # Date.current instead.
      raise "Date.today should not be called!"
    end
  end

  def setup
    super
    Setting.non_working_week_days = [6, 7]
    @issue1 = issues(:issue_01)
    @issue2 = issues(:issue_02)
    @issue3 = issues(:issue_03)
  end

  def teardown
    super
    logout_user
  end

  def test_create_recurrence
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018, 10, 1))
    create_recurrence
  end

  def test_renew_anchor_mode_fixed_mode_daily
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,10,1), due_date: Date.new(2018,10,5))

    IssueRecurrence::FIXED_MODES.each do |am|
      travel_to(Date.new(2018,9,21))
      create_recurrence(anchor_mode: am,
                        mode: :daily,
                        multiplier: 10)
      renew_all(0)
      travel_to(Date.new(2018,9,30))
      renew_all(0)
      travel_to(Date.new(2018,10,1))
      issue1 = renew_all(1)
      assert_equal Date.new(2018,10,11), issue1.start_date
      assert_equal Date.new(2018,10,15), issue1.due_date
      travel_to(Date.new(2018,10,9))
      renew_all(0)
      travel_to(Date.new(2018,10,30))
      issue2, issue3 = renew_all(2)
      assert_equal Date.new(2018,10,21), issue2.start_date
      assert_equal Date.new(2018,10,25), issue2.due_date
      assert_equal Date.new(2018,10,31), issue3.start_date
      assert_equal Date.new(2018,11,4), issue3.due_date
      travel_to(Date.new(2018,10,31))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_daily_wday
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,13), due_date: Date.new(2018,10,2))

    IssueRecurrence::FIXED_MODES.each do |am|
      travel_to(Date.new(2018,8,12))
      create_recurrence(anchor_mode: am,
                        mode: :daily_wday,
                        multiplier: 2)
      renew_all(0)
      travel_to(Date.new(2018,9,12))
      renew_all(0)
      travel_to(Date.new(2018,9,13))
      r1 = renew_all(1)
      assert_equal Date.new(2018,9,17), r1.start_date
      assert_equal Date.new(2018,10,4), r1.due_date
      travel_to(Date.new(2018,9,16))
      renew_all(0)
      travel_to(Date.new(2018,9,20))
      r2, r3 = renew_all(2)
      assert_equal Date.new(2018,9,19), r2.start_date
      assert_equal Date.new(2018,10,8), r2.due_date
      assert_equal Date.new(2018,9,21), r3.start_date
      assert_equal Date.new(2018,10,10), r3.due_date
      travel_to(Date.new(2018,9,21))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_weekly
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,8,12), due_date: Date.new(2018,8,20))

    IssueRecurrence::FIXED_MODES.each do |am|
      travel_to(Date.new(2018,7,29))
      create_recurrence(anchor_mode: am,
                        mode: :weekly,
                        multiplier: 4)
      renew_all(0)
      travel_to(Date.new(2018,8,12))
      issue1 = renew_all(1)
      assert_equal Date.new(2018,9,9), issue1.start_date
      assert_equal Date.new(2018,9,17), issue1.due_date
      travel_to(Date.new(2018,9,8))
      renew_all(0)
      travel_to(Date.new(2018,11,3))
      issue2, issue3 = renew_all(2)
      assert_equal Date.new(2018,10,7), issue2.start_date
      assert_equal Date.new(2018,10,15), issue2.due_date
      assert_equal Date.new(2018,11,4), issue3.start_date
      assert_equal Date.new(2018,11,12), issue3.due_date
      travel_to(Date.new(2018,11,4))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_monthly_day_from_first
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,8), due_date: Date.new(2018,10,2))

    IssueRecurrence::FIXED_MODES.each do |am|
      travel_to(Date.new(2017,9,8))
      create_recurrence(anchor_mode: am,
                        mode: :monthly_start_day_from_first,
                        multiplier: 2)
      renew_all(0)
      travel_to(Date.new(2017,1,8))
      renew_all(0)
      travel_to(Date.new(2018,9,8))
      issue1 = renew_all(1)
      assert_equal Date.new(2018,11,8), issue1.start_date
      assert_equal Date.new(2018,12,2), issue1.due_date
      travel_to(Date.new(2018,11,7))
      renew_all(0)
      travel_to(Date.new(2019,3,7))
      issue2, issue3 = renew_all(2)
      assert_equal Date.new(2019,1,8), issue2.start_date
      assert_equal Date.new(2019,2,1), issue2.due_date
      assert_equal Date.new(2019,3,8), issue3.start_date
      assert_equal Date.new(2019,4,1), issue3.due_date
      travel_to(Date.new(2019,3,8))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_monthly_day_to_last
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,22), due_date: Date.new(2018,10,10))

    IssueRecurrence::FIXED_MODES.each do |am|
      travel_to(Date.new(2018,3,22))
      create_recurrence(anchor_mode: am,
                        mode: :monthly_due_day_to_last,
                        multiplier: 3)
      renew_all(0)
      travel_to(Date.new(2018,5,21))
      renew_all(0)
      travel_to(Date.new(2018,9,22))
      issue1 = renew_all(1)
      assert_equal Date.new(2018,12,23), issue1.start_date
      assert_equal Date.new(2019,1,10), issue1.due_date
      travel_to(Date.new(2018,12,22))
      renew_all(0)
      travel_to(Date.new(2019,6,21))
      issue2, issue3 = renew_all(2)
      assert_equal Date.new(2019,3,22), issue2.start_date
      assert_equal Date.new(2019,4,9), issue2.due_date
      assert_equal Date.new(2019,6,22), issue3.start_date
      assert_equal Date.new(2019,7,10), issue3.due_date
      travel_to(Date.new(2019,6,22))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_monthly_dow_from_first
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,22), due_date: Date.new(2018,10,10))

    IssueRecurrence::FIXED_MODES.each do |am|
      travel_to(Date.new(2018,3,22))
      create_recurrence(anchor_mode: am,
                        mode: :monthly_start_dow_from_first,
                        multiplier: 2)
      renew_all(0)
      travel_to(Date.new(2018,5,21))
      renew_all(0)
      travel_to(Date.new(2018,9,22))
      issue1 = renew_all(1)
      assert_equal Date.new(2018,11,24), issue1.start_date
      assert_equal Date.new(2018,12,12), issue1.due_date
      travel_to(Date.new(2018,11,22))
      renew_all(0)
      travel_to(Date.new(2019,3,22))
      issue2, issue3 = renew_all(2)
      assert_equal Date.new(2019,1,26), issue2.start_date
      assert_equal Date.new(2019,2,13), issue2.due_date
      assert_equal Date.new(2019,3,23), issue3.start_date
      assert_equal Date.new(2019,4,10), issue3.due_date
      travel_to(Date.new(2019,3,23))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_monthly_dow_to_last
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,3), due_date: Date.new(2018,9,15))

    IssueRecurrence::FIXED_MODES.each do |am|
      travel_to(Date.new(2018,6,3))
      create_recurrence(anchor_mode: am,
                        mode: :monthly_due_dow_to_last,
                        multiplier: 1)
      renew_all(0)
      travel_to(Date.new(2018,8,3))
      renew_all(0)
      travel_to(Date.new(2018,9,3))
      issue1 = renew_all(1)
      assert_equal Date.new(2018,10,1), issue1.start_date
      assert_equal Date.new(2018,10,13), issue1.due_date
      travel_to(Date.new(2018,9,30))
      renew_all(0)
      travel_to(Date.new(2018,12,2))
      issue2, issue3 = renew_all(2)
      assert_equal Date.new(2018,10,29), issue2.start_date
      assert_equal Date.new(2018,11,10), issue2.due_date
      assert_equal Date.new(2018,12,3), issue3.start_date
      assert_equal Date.new(2018,12,15), issue3.due_date
      travel_to(Date.new(2018,12,3))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_monthly_wday_from_first
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,10,1), due_date: Date.new(2018,10,3))

    IssueRecurrence::FIXED_MODES.each do |am|
      travel_to(Date.new(2018,4,1))
      create_recurrence(anchor_mode: am,
                        mode: :monthly_due_wday_from_first,
                        multiplier: 1)
      renew_all(0)
      travel_to(Date.new(2018,6,1))
      renew_all(0)
      travel_to(Date.new(2018,10,1))
      issue1 = renew_all(1)
      assert_equal Date.new(2018,11,1), issue1.start_date
      assert_equal Date.new(2018,11,5), issue1.due_date
      travel_to(Date.new(2018,10,31))
      renew_all(0)
      travel_to(Date.new(2018,12,31))
      issue2, issue3 = renew_all(2)
      assert_equal Date.new(2018,12,3), issue2.start_date
      assert_equal Date.new(2018,12,5), issue2.due_date
      assert_equal Date.new(2019,1,1), issue3.start_date
      assert_equal Date.new(2019,1,3), issue3.due_date
      travel_to(Date.new(2019,1,1))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_monthly_wday_to_last
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,26), due_date: Date.new(2018,9,28))

    IssueRecurrence::FIXED_MODES.each do |am|
      travel_to(Date.new(2018,3,26))
      create_recurrence(anchor_mode: am,
                        mode: :monthly_start_wday_to_last,
                        multiplier: 2)
      renew_all(0)
      travel_to(Date.new(2018,5,26))
      renew_all(0)
      travel_to(Date.new(2018,9,26))
      issue1 = renew_all(1)
      assert_equal Date.new(2018,11,28), issue1.start_date
      assert_equal Date.new(2018,11,30), issue1.due_date
      travel_to(Date.new(2018,11,27))
      renew_all(0)
      travel_to(Date.new(2019,3,26))
      issue2, issue3 = renew_all(2)
      assert_equal Date.new(2019,1,29), issue2.start_date
      assert_equal Date.new(2019,1,31), issue2.due_date
      assert_equal Date.new(2019,3,27), issue3.start_date
      assert_equal Date.new(2019,3,29), issue3.due_date
      travel_to(Date.new(2019,3,27))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_yearly
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,8,19), due_date: Date.new(2018,9,5))

    IssueRecurrence::FIXED_MODES.each do |am|
      travel_to(Date.new(2017,8,2))
      create_recurrence(anchor_mode: am,
                        mode: :yearly,
                        multiplier: 1)
      renew_all(0)
      travel_to(Date.new(2018,8,18))
      renew_all(0)
      travel_to(Date.new(2018,8,19))
      issue1 = renew_all(1)
      assert_equal Date.new(2019,8,19), issue1.start_date
      assert_equal Date.new(2019,9,5), issue1.due_date
      travel_to(Date.new(2019,8,18))
      renew_all(0)
      travel_to(Date.new(2021,8,18))
      issue2, issue3 = renew_all(2)
      assert_equal Date.new(2020,8,19), issue2.start_date
      assert_equal Date.new(2020,9,5), issue2.due_date
      assert_equal Date.new(2021,8,19), issue3.start_date
      assert_equal Date.new(2021,9,5), issue3.due_date
      travel_to(Date.new(2021,8,20))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_flexible_mode_daily
    log_user 'alice', 'foo'
    @issue1.update(start_date: Date.new(2018,10,1), due_date: Date.new(2018,10,5))

    travel_to(Date.new(2018,9,21))
    create_recurrence(anchor_mode: :last_issue_flexible,
                      mode: :daily,
                      multiplier: 10)
    renew_all(0)
    travel_to(Date.new(2018,9,30))
    renew_all(0)
    travel_to(Date.new(2018,10,7))
    # closed after due
    close_issue(@issue1)
    issue1 = renew_all(1)
    assert_equal Date.new(2018,10,13), issue1.start_date
    assert_equal Date.new(2018,10,17), issue1.due_date
    travel_to(Date.new(2018,10,15))
    renew_all(0)
    # closed between start and due
    close_issue(issue1)
    issue2 = renew_all(1)
    assert_equal Date.new(2018,10,21), issue2.start_date
    assert_equal Date.new(2018,10,25), issue2.due_date
    travel_to(Date.new(2018,10,19))
    renew_all(0)
    # closed before start
    close_issue(issue2)
    travel_to(Date.new(2018,10,22))
    issue3 = renew_all(1)
    assert_equal Date.new(2018,10,25), issue3.start_date
    assert_equal Date.new(2018,10,29), issue3.due_date
    travel_to(Date.new(2018,11,18))
    close_issue(issue3)
    travel_to(Date.new(2018,12,31))
    renew_all(1)
    renew_all(0)
  end

  def test_renew_anchor_mode_flexible_on_delay_mode_daily
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,10,1), due_date: Date.new(2018,10,5))

    travel_to(Date.new(2018,9,21))
    create_recurrence(anchor_mode: :last_issue_flexible_on_delay,
                      mode: :daily,
                      multiplier: 10)
    renew_all(0)
    travel_to(Date.new(2018,9,30))
    renew_all(0)
    travel_to(Date.new(2018,10,7))
    # closed after due
    close_issue(@issue1)
    issue1 = renew_all(1)
    assert_equal Date.new(2018,10,13), issue1.start_date
    assert_equal Date.new(2018,10,17), issue1.due_date
    travel_to(Date.new(2018,10,15))
    renew_all(0)
    # closed between start and due
    close_issue(issue1)
    issue2 = renew_all(1)
    assert_equal Date.new(2018,10,23), issue2.start_date
    assert_equal Date.new(2018,10,27), issue2.due_date
    travel_to(Date.new(2018,10,21))
    renew_all(0)
    # closed before start
    close_issue(issue2)
    travel_to(Date.new(2018,10,25))
    issue3 = renew_all(1)
    assert_equal Date.new(2018,11,2), issue3.start_date
    assert_equal Date.new(2018,11,6), issue3.due_date
    travel_to(Date.new(2018,11,18))
    close_issue(issue3)
    travel_to(Date.new(2018,12,31))
    renew_all(1)
    renew_all(0)
  end

  def test_renew_huge_multiplier
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,25), due_date: Date.new(2018,10,4))

    items = {
      daily: [Date.new(2021,6,21), Date.new(2021,6,30)],
      weekly: [Date.new(2037,11,24), Date.new(2037,12,3)],
      monthly_start_day_from_first: [Date.new(2102,1,25), Date.new(2102,2,3)],
      monthly_due_day_from_first: [Date.new(2102,1,26), Date.new(2102,2,4)],
      monthly_start_day_to_last: [Date.new(2102,1,26), Date.new(2102,2,4)],
      monthly_due_day_to_last: [Date.new(2102,1,23), Date.new(2102,2,1)],
      monthly_start_dow_from_first: [Date.new(2102,1,24), Date.new(2102,2,2)],
      monthly_due_dow_from_first: [Date.new(2102,1,24), Date.new(2102,2,2)],
      monthly_start_dow_to_last: [Date.new(2102,1,31), Date.new(2102,2,9)],
      monthly_due_dow_to_last: [Date.new(2102,1,24), Date.new(2102,2,2)],
      monthly_start_wday_from_first: [Date.new(2102,1,24), Date.new(2102,2,2)],
      monthly_due_wday_from_first: [Date.new(2102,1,26), Date.new(2102,2,6)],
      monthly_start_wday_to_last: [Date.new(2102,1,26), Date.new(2102,2,6)],
      monthly_due_wday_to_last: [Date.new(2102,1,23), Date.new(2102,2,1)],
      yearly: [Date.new(3018,9,25), Date.new(3018,10,4)],
    }
    items.each do |m, (start, due)|
      travel_to(Date.new(2018,10,21))
      create_recurrence(anchor_mode: :last_issue_fixed,
                        mode: m,
                        multiplier: 1000)
      issue1 = renew_all(1)
      assert_equal start, issue1.start_date
      assert_equal due, issue1.due_date
    end
  end

  def test_renew_closed_on_cleared_for_new_recurrences_of_closed_issue
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,25), due_date: Date.new(2018,10,4))

    assert_nil @issue1.closed_on
    travel_to(Date.new(2018,10,22))
    create_recurrence(anchor_mode: :first_issue_fixed,
                      mode: :weekly,
                      multiplier: 2)
    close_issue(@issue1)
    @issue1.reload
    assert_not_nil @issue1.closed_on
    r1, r2 = renew_all(2)
    assert_nil r1.closed_on
    assert_nil r2.closed_on
  end

  def test_renew_issue_with_timespan_much_larger_than_recurrence_period
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,8,20), due_date: Date.new(2019,1,10))

    create_recurrence(anchor_mode: :last_issue_fixed,
                      mode: :daily,
                      multiplier: 3)
    travel_to(Date.new(2018,9,1))
    *, r5 = renew_all(5)
    assert_equal Date.new(2018,9,4), r5.start_date
    assert_equal Date.new(2019,1,25), r5.due_date
  end

  def test_renew_anchor_mode_fixed_issue_one_date_not_set
    log_user 'alice', 'foo'

    dates = {
      {start: Date.new(2018,10,10), due: nil} =>
      [
        [Date.new(2018,10,9), nil],
        [Date.new(2018,10,10), {start: Date.new(2018,11,14), due: nil}],
        [Date.new(2018,11,13), nil],
        [Date.new(2018,11,14), {start: Date.new(2018,12,12), due: nil}]
      ],
      {start: nil, due: Date.new(2018,10,15)} =>
      [
        [Date.new(2018,10,14), nil],
        [Date.new(2018,10,15), {start: nil, due: Date.new(2018,11,19)}],
        [Date.new(2018,11,18), nil],
        [Date.new(2018,11,19), {start: nil, due: Date.new(2018,12,17)}]
      ]
    }

    IssueRecurrence::FIXED_MODES.each do |am|
      dates.each do |issue_dates, setup_dates|
        @issue1.reload
        @issue1.update!(start_date: issue_dates[:start], due_date: issue_dates[:due])

        mode = issue_dates[:start].present? ? :monthly_start_dow_from_first :
          :monthly_due_dow_from_first
        create_recurrence(anchor_mode: am, mode: mode, multiplier: 1)

        setup_dates.each do |t, r_dates|
          travel_to(t)
          r = renew_all(r_dates.present? ? 1 : 0)
          if r_dates.present?
            if r_dates[:start].present?
              assert_equal r_dates[:start], r.start_date
            else
              assert_nil r.start_date
            end
            if r_dates[:due].present?
              assert_equal r_dates[:due], r.due_date
            else
              assert_nil r.due_date
            end
          end
        end
      end
    end
  end

  def test_renew_anchor_mode_flexible_issue_one_date_not_set
    log_user 'alice', 'foo'

    dates = {
      {start: Date.new(2018,10,10), due: nil} =>
      [
        [Date.new(2018,10,12), false, nil],
        [Date.new(2018,10,15), true, {start: Date.new(2018,11,19), due: nil}],
        [Date.new(2018,11,25), false, nil],
        [Date.new(2018,11,30), true, {start: Date.new(2018,12,28), due: nil}]
      ],
      {start: nil, due: Date.new(2018,10,15)} =>
      [
        [Date.new(2018,10,19), false, nil],
        [Date.new(2018,10,26), true, {start: nil, due: Date.new(2018,11,23)}],
        [Date.new(2018,12,6), false, nil],
        [Date.new(2018,12,8), true, {start: nil, due: Date.new(2019,1,12)}]
      ]
    }

    dates.each do |issue_dates, setup_dates|
      @issue1.update!(start_date: issue_dates[:start], due_date: issue_dates[:due])
      reopen_issue(@issue1) if @issue1.closed?

      mode = issue_dates[:start].present? ? :monthly_start_dow_from_first :
        :monthly_due_dow_from_first
      ir = create_recurrence(anchor_mode: :last_issue_flexible, mode: mode, multiplier: 1)

      setup_dates.each do |t, close, r_dates|
        travel_to(t)
        close_issue(ir.last_issue || @issue1) if close
        ir.reload
        r = renew_all(r_dates.present? ? 1 : 0)
        if r_dates.present?
          if r_dates[:start].present?
            assert_equal r_dates[:start], r.start_date
          else
            assert_nil r.start_date
          end
          if r_dates[:due].present?
            assert_equal r_dates[:due], r.due_date
          else
            assert_nil r.due_date
          end
        end
      end
    end
  end

  def test_create_anchor_mode_fixed_issue_dates_not_set_should_fail
    log_user 'alice', 'foo'
    @issue1.update!(start_date: nil, due_date: nil)

    IssueRecurrence::FIXED_MODES.each do |am|
      errors = create_recurrence_should_fail(anchor_mode: am)
      assert errors.added?(:anchor_mode, :blank_dates_flexible_only)
    end
  end

  def test_renew_anchor_mode_flexible_issue_dates_not_set
    log_user 'alice', 'foo'

    dates = [
      [Date.new(2018,10,12), false, nil],
      [Date.new(2018,10,15), true, {start: nil, due: Date.new(2018,10,22)}],
      [Date.new(2018,11,25), false, nil],
      [Date.new(2018,11,30), true, {start: nil, due: Date.new(2018,12,7)}]
    ]

    @issue1.update!(start_date: nil, due_date: nil)
    assert !@issue1.closed?

    ir = create_recurrence(anchor_mode: :last_issue_flexible)

    dates.each do |t, close, r_dates|
      travel_to(t)
      close_issue(ir.last_issue || @issue1) if close
      ir.reload
      r = renew_all(r_dates.present? ? 1 : 0)
      if r_dates.present?
        if r_dates[:start].present?
          assert_equal r_dates[:start], r.start_date
        else
          assert_nil r.start_date
        end
        if r_dates[:due].present?
          assert_equal r_dates[:due], r.due_date
        else
          assert_nil r.due_date
        end
      end
    end
  end

  def test_renew_mode_monthly_should_not_overflow_in_shorter_month
    log_user 'alice', 'foo'

    dates = [
      [Date.new(2019,1,29), Date.new(2019,1,31), :monthly_start_day_from_first,
       Date.new(2019,2,28), Date.new(2019,3,2)],
      [Date.new(2019,1,29), Date.new(2019,1,31), :monthly_due_day_from_first,
       Date.new(2019,2,26), Date.new(2019,2,28)],
      [Date.new(2019,1,1), Date.new(2019,1,3), :monthly_start_day_to_last,
       Date.new(2019,2,1), Date.new(2019,2,3)],
      [Date.new(2019,1,1), Date.new(2019,1,3), :monthly_due_day_to_last,
       Date.new(2019,1,30), Date.new(2019,2,1)],
      [Date.new(2019,1,29), Date.new(2019,1,31), :monthly_start_dow_from_first,
       Date.new(2019,2,26), Date.new(2019,2,28)],
      [Date.new(2019,1,29), Date.new(2019,1,31), :monthly_due_dow_from_first,
       Date.new(2019,2,26), Date.new(2019,2,28)],
      [Date.new(2019,1,1), Date.new(2019,1,3), :monthly_start_dow_to_last,
       Date.new(2019,2,5), Date.new(2019,2,7)],
      [Date.new(2019,1,1), Date.new(2019,1,3), :monthly_due_dow_to_last,
       Date.new(2019,2,5), Date.new(2019,2,7)],
      [Date.new(2019,1,29), Date.new(2019,1,31), :monthly_start_wday_from_first,
       Date.new(2019,2,28), Date.new(2019,3,4)],
      [Date.new(2019,1,29), Date.new(2019,1,31), :monthly_due_wday_from_first,
       Date.new(2019,2,26), Date.new(2019,2,28)],
      [Date.new(2019,1,1), Date.new(2019,1,3), :monthly_start_wday_to_last,
       Date.new(2019,2,1), Date.new(2019,2,5)],
      [Date.new(2019,1,1), Date.new(2019,1,3), :monthly_due_wday_to_last,
       Date.new(2019,1,30), Date.new(2019,2,1)],
    ]

    dates.each do |start, due, mode, r_start, r_due|
      travel_to(start)
      @issue1.update!(start_date: start, due_date: due)

      ir = create_recurrence(mode: mode)

      r = renew_all(1)
      assert_equal r_start, r.start_date
      assert_equal r_due, r.due_date
    end
  end

  def test_renew_with_delay_anchor_mode_fixed
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    IssueRecurrence::FIXED_MODES.each do |am|
      travel_to(Date.new(2018,9,14))
      create_recurrence(anchor_mode: am,
                        mode: :monthly_start_day_from_first,
                        delay_mode: :day,
                        delay_multiplier: 10)

      renew_all(0)
      travel_to(Date.new(2018,9,15))
      r1 = renew_all(1)
      assert_equal Date.new(2018,10,25), r1.start_date
      assert_equal Date.new(2018,10,30), r1.due_date

      travel_to(Date.new(2018,10,24))
      renew_all(0)

      travel_to(Date.new(2018,10,25))
      r2 = renew_all(1)
      assert_equal Date.new(2018,11,25), r2.start_date
      assert_equal Date.new(2018,11,30), r2.due_date
    end
  end

  def test_create_anchor_mode_flexible_with_delay_should_fail
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    IssueRecurrence::FLEXIBLE_MODES.each do |am|
      errors = create_recurrence_should_fail(anchor_mode: am,
                        mode: :monthly_start_day_from_first,
                        delay_mode: :day,
                        delay_multiplier: 10)
      assert errors.added?(:anchor_mode, :delay_fixed_only)
    end
  end

  def test_renew_sets_recurrence_of_for_new_recurrence_and_subtask
    log_user 'alice', 'foo'
    @issue2.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))
    set_parent_issue(@issue1, @issue2)
    # Need to reload. Parent dates are computed from children by default.
    @issue1.reload

    create_recurrence(include_subtasks: true)
    travel_to(@issue1.start_date)
    r1, r2 = renew_all(2)
    assert_equal @issue1, r1.recurrence_of
    assert_equal @issue1, r2.recurrence_of
  end

  def test_renew_subtasks_mode_weekly
    log_user 'alice', 'foo'
    @issue2.update!(start_date: Date.new(2018,9,25), due_date: Date.new(2018,10,5))
    @issue3.update!(start_date: Date.new(2018,9,20), due_date: Date.new(2018,9,30))
    set_parent_issue(@issue1, @issue2)
    set_parent_issue(@issue1, @issue3)
    @issue1.reload

    create_recurrence(include_subtasks: true, mode: :weekly)
    travel_to(@issue1.start_date-1)
    renew_all(0)
    travel_to(@issue1.start_date)
    r1, * = renew_all(3)
    assert_equal Date.new(2018,9,27), r1.start_date
    assert_equal Date.new(2018,10,12), r1.due_date
    r2 = IssueRelation.find_by(issue_from: @issue2, relation_type: 'copied_to').issue_to
    assert_equal Date.new(2018,10,2), r2.start_date
    assert_equal Date.new(2018,10,12), r2.due_date
    r3 = IssueRelation.find_by(issue_from: @issue3, relation_type: 'copied_to').issue_to
    assert_equal Date.new(2018,9,27), r3.start_date
    assert_equal Date.new(2018,10,7), r3.due_date
  end

  def test_renew_subtasks_mode_monthly_start
    log_user 'alice', 'foo'
    @issue2.update!(start_date: Date.new(2018,9,25), due_date: Date.new(2018,10,5))
    @issue3.update!(start_date: Date.new(2018,9,20), due_date: Date.new(2018,9,30))
    set_parent_issue(@issue1, @issue2)
    set_parent_issue(@issue1, @issue3)
    @issue1.reload

    create_recurrence(include_subtasks: true, mode: :monthly_start_dow_from_first)
    travel_to(@issue1.start_date-1)
    renew_all(0)
    travel_to(@issue1.start_date)
    r1, * = renew_all(3)
    assert_equal Date.new(2018,10,18), r1.start_date
    assert_equal Date.new(2018,11,2), r1.due_date
    r2 = IssueRelation.find_by(issue_from: @issue2, relation_type: 'copied_to').issue_to
    assert_equal Date.new(2018,10,23), r2.start_date
    assert_equal Date.new(2018,11,2), r2.due_date
    r3 = IssueRelation.find_by(issue_from: @issue3, relation_type: 'copied_to').issue_to
    assert_equal Date.new(2018,10,18), r3.start_date
    assert_equal Date.new(2018,10,28), r3.due_date
  end

  def test_renew_subtasks_mode_monthly_due
    log_user 'alice', 'foo'
    @issue2.update!(start_date: Date.new(2018,9,25), due_date: Date.new(2018,10,5))
    @issue3.update!(start_date: Date.new(2018,9,20), due_date: Date.new(2018,9,30))
    set_parent_issue(@issue1, @issue2)
    set_parent_issue(@issue1, @issue3)
    @issue1.reload

    create_recurrence(include_subtasks: true, mode: :monthly_due_wday_to_last)
    travel_to(@issue1.start_date-1)
    renew_all(0)
    travel_to(@issue1.start_date)
    r1, * = renew_all(3)
    assert_equal Date.new(2018,10,22), r1.start_date
    assert_equal Date.new(2018,11,6), r1.due_date
    r2 = IssueRelation.find_by(issue_from: @issue2, relation_type: 'copied_to').issue_to
    assert_equal Date.new(2018,10,25), r2.start_date
    assert_equal Date.new(2018,11,6), r2.due_date
    r3 = IssueRelation.find_by(issue_from: @issue3, relation_type: 'copied_to').issue_to
    assert_equal Date.new(2018,10,22), r3.start_date
    assert_equal Date.new(2018,10,31), r3.due_date
  end

  def test_renew_creation_mode_copy_first
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    create_recurrence(creation_mode: :copy_first)
    travel_to(@issue1.start_date)
    r1 = renew_all(1)
    travel_to(r1.start_date)
    r2 = renew_all(1)

    no_rel = IssueRelation.find_by(issue_from: r1, relation_type: 'copied_to')
    assert_nil no_rel
    rel = IssueRelation.find_by(issue_to: r2, relation_type: 'copied_to')
    assert_not_nil rel
    assert_equal rel.issue_from, @issue1
  end

  def test_renew_creation_mode_copy_last
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    create_recurrence(creation_mode: :copy_last)
    travel_to(@issue1.start_date)
    r1 = renew_all(1)
    travel_to(r1.start_date)
    r2 = renew_all(1)

    rel1 = IssueRelation.find_by(issue_from: @issue1, relation_type: 'copied_to')
    assert_not_nil rel1
    assert_equal rel1.issue_to, r1
    rel2 = IssueRelation.find_by(issue_from: r1, relation_type: 'copied_to')
    assert_not_nil rel2
    assert_equal rel2.issue_to, r2
  end

  def test_renew_creation_mode_in_place
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    create_recurrence(creation_mode: :in_place, anchor_mode: :last_issue_flexible)
    travel_to(Date.new(2018,9,18))
    renew_all(0)
    @issue1.reload
    assert_equal Date.new(2018,9,15), @issue1.start_date

    close_issue(@issue1)
    renew_all(0)
    @issue1.reload
    assert_equal Date.new(2018,9,20), @issue1.start_date
    assert_equal Date.new(2018,9,25), @issue1.due_date
    assert !@issue1.closed?
  end

  def test_create_anchor_mode_fixed_with_creation_mode_in_place_should_fail
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    IssueRecurrence::FIXED_MODES.each do |am|
      errors = create_recurrence_should_fail(creation_mode: :in_place, anchor_mode: am)
      assert errors.added?(:anchor_mode, :in_place_flexible_only)
    end
  end

  def test_renew_applies_author_id_configuration_setting
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    Setting.plugin_issue_recurring['author_id'] = 0
    assert_equal 0, Setting.plugin_issue_recurring['author_id']
    assert_equal users(:bob), @issue1.author

    create_recurrence(creation_mode: :copy_first)

    travel_to(@issue1.start_date)
    r1 = renew_all(1)
    assert_equal users(:bob), r1.author

    Setting.plugin_issue_recurring['author_id'] = users(:charlie).id
    assert_equal users(:charlie).id, Setting.plugin_issue_recurring['author_id']

    travel_to(r1.start_date)
    r2 = renew_all(1)
    assert_equal users(:charlie), r2.author
  end

  def test_renew_applies_keep_assignee_configuration_setting
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    Setting.plugin_issue_recurring['keep_assignee'] = false
    assert !Setting.plugin_issue_recurring['keep_assignee']
    assert_equal users(:alice), @issue1.assigned_to
    assert_equal users(:gopher), @issue1.project.default_assigned_to

    create_recurrence(creation_mode: :copy_first)

    travel_to(@issue1.start_date)
    r1 = renew_all(1)
    assert_equal users(:gopher), r1.assigned_to

    Setting.plugin_issue_recurring['keep_assignee'] = true
    assert Setting.plugin_issue_recurring['keep_assignee']

    travel_to(r1.start_date)
    r2 = renew_all(1)
    assert_equal users(:alice), r2.assigned_to
  end

  def test_renew_applies_add_journal_configuration_setting
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    create_recurrence(creation_mode: :copy_first)

    Setting.plugin_issue_recurring['add_journal'] = false
    assert !Setting.plugin_issue_recurring['add_journal']

    travel_to(@issue1.start_date)
    r1 = nil
    assert_no_difference 'Journal.count' do
      r1 = renew_all(1)
    end

    Setting.plugin_issue_recurring['add_journal'] = true
    assert Setting.plugin_issue_recurring['add_journal']

    travel_to(r1.start_date)
    assert_difference 'Journal.count', 1 do
      renew_all(1)
    end
    assert_equal @issue1.author, Journal.last.user
  end

  def test_renew_anchor_mode_first_issue_fixed_after_first_and_last_issue_date_change
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    create_recurrence(anchor_mode: :first_issue_fixed)

    travel_to(@issue1.start_date)
    r1 = renew_all(1)
    assert_equal Date.new(2018,9,22), r1.start_date
    assert_equal Date.new(2018,9,27), r1.due_date

    r1.update!(start_date: Date.new(2018,7,4), due_date: Date.new(2018,7,15))
    travel_to(Date.new(2018,9,21))
    renew_all(0)
    travel_to(Date.new(2018,9,22))
    r2 = renew_all(1)
    assert_equal Date.new(2018,9,29), r2.start_date
    assert_equal Date.new(2018,10,4), r2.due_date

    @issue1.update!(start_date: Date.new(2018,9,10), due_date: Date.new(2018,9,25))
    travel_to(Date.new(2018,9,23))
    renew_all(0)
    travel_to(Date.new(2018,9,24))
    r3 = renew_all(1)
    assert_equal Date.new(2018,10,1), r3.start_date
    assert_equal Date.new(2018,10,16), r3.due_date
  end

  def test_renew_anchor_mode_last_issue_fixed_after_first_and_last_issue_date_change
    log_user 'alice', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    create_recurrence(anchor_mode: :last_issue_fixed)

    travel_to(@issue1.start_date)
    r1 = renew_all(1)
    assert_equal Date.new(2018,9,22), r1.start_date
    assert_equal Date.new(2018,9,27), r1.due_date

    @issue1.update!(start_date: Date.new(2018,9,10), due_date: Date.new(2018,9,25))
    travel_to(Date.new(2018,9,21))
    renew_all(0)
    travel_to(Date.new(2018,9,22))
    r2 = renew_all(1)
    assert_equal Date.new(2018,9,29), r2.start_date
    assert_equal Date.new(2018,10,4), r2.due_date

    r2.update!(start_date: Date.new(2018,7,4), due_date: Date.new(2018,7,15))
    travel_to(Date.new(2018,7,3))
    renew_all(0)
    travel_to(Date.new(2018,7,4))
    r3 = renew_all(1)
    assert_equal Date.new(2018,7,11), r3.start_date
    assert_equal Date.new(2018,7,22), r3.due_date
  end

  # TODO:
  # - error logging
  # - permissions
  # - show views: issue/issue recurrences/settings
end

