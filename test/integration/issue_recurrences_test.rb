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

  def test_renew_anchor_mode_fixed_mode_daily
    log_user 'alice', 'foo'
    @issue1.start_date = Date.new(2018,10,1)
    @issue1.due_date = Date.new(2018,10,5)
    @issue1.save!

    [:first_issue_fixed, :last_issue_fixed].each do |am|
      travel_to(Date.new(2018,9,21))
      create_recurrence(anchor_mode: am,
                        mode: :daily,
                        multiplier: 10)
      renew_all(0)
      travel_to(Date.new(2018,9,30))
      renew_all(0)
      travel_to(Date.new(2018,10,1))
      issue1 = renew_all(1).first
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

  def test_renew_anchor_mode_fixed_mode_weekly
    log_user 'alice', 'foo'
    @issue1.start_date = Date.new(2018,8,12)
    @issue1.due_date = Date.new(2018,8,20)
    @issue1.save!

    [:first_issue_fixed, :last_issue_fixed].each do |am|
      travel_to(Date.new(2018,7,29))
      create_recurrence(anchor_mode: am,
                        mode: :weekly,
                        multiplier: 4)
      renew_all(0)
      travel_to(Date.new(2018,8,12))
      issue1 = renew_all(1).first
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
    @issue1.start_date = Date.new(2018,9,8)
    @issue1.due_date = Date.new(2018,10,2)
    @issue1.save!

    [:first_issue_fixed, :last_issue_fixed].each do |am|
      travel_to(Date.new(2017,9,8))
      create_recurrence(anchor_mode: am,
                        mode: :monthly_day_from_first,
                        multiplier: 2)
      renew_all(0)
      travel_to(Date.new(2017,1,8))
      renew_all(0)
      travel_to(Date.new(2018,9,8))
      issue1 = renew_all(1).first
      assert_equal Date.new(2018,11,8), issue1.start_date
      assert_equal Date.new(2018,12,2), issue1.due_date
      travel_to(Date.new(2018,11,7))
      renew_all(0)
      travel_to(Date.new(2019,3,7))
      issue2, issue3 = renew_all(2)
      assert_equal Date.new(2019,1,8), issue2.start_date
      assert_equal Date.new(2019,2,2), issue2.due_date
      assert_equal Date.new(2019,3,8), issue3.start_date
      assert_equal Date.new(2019,4,2), issue3.due_date
      travel_to(Date.new(2019,3,8))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_monthly_day_to_last
    log_user 'alice', 'foo'
    @issue1.start_date = Date.new(2018,9,22)
    @issue1.due_date = Date.new(2018,10,10)
    @issue1.save!

    [:first_issue_fixed, :last_issue_fixed].each do |am|
      travel_to(Date.new(2018,3,22))
      create_recurrence(anchor_mode: am,
                        mode: :monthly_day_to_last,
                        multiplier: 3)
      renew_all(0)
      travel_to(Date.new(2018,5,21))
      renew_all(0)
      travel_to(Date.new(2018,9,22))
      issue1 = renew_all(1).first
      assert_equal Date.new(2018,12,23), issue1.start_date
      assert_equal Date.new(2019,1,10), issue1.due_date
      travel_to(Date.new(2018,12,22))
      renew_all(0)
      travel_to(Date.new(2019,6,21))
      issue2, issue3 = renew_all(2)
      assert_equal Date.new(2019,3,23), issue2.start_date
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
    @issue1.start_date = Date.new(2018,9,22)
    @issue1.due_date = Date.new(2018,10,10)
    @issue1.save!

    [:first_issue_fixed, :last_issue_fixed].each do |am|
      travel_to(Date.new(2018,3,22))
      create_recurrence(anchor_mode: am,
                        mode: :monthly_dow_from_first,
                        multiplier: 2)
      renew_all(0)
      travel_to(Date.new(2018,5,21))
      renew_all(0)
      travel_to(Date.new(2018,9,22))
      issue1 = renew_all(1).first
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
    @issue1.start_date = Date.new(2018,9,3)
    @issue1.due_date = Date.new(2018,9,15)
    @issue1.save!

    [:first_issue_fixed, :last_issue_fixed].each do |am|
      travel_to(Date.new(2018,6,3))
      create_recurrence(anchor_mode: am,
                        mode: :monthly_dow_to_last,
                        multiplier: 1)
      renew_all(0)
      travel_to(Date.new(2018,8,3))
      renew_all(0)
      travel_to(Date.new(2018,9,3))
      issue1 = renew_all(1).first
      assert_equal Date.new(2018,10,8), issue1.start_date
      assert_equal Date.new(2018,10,13), issue1.due_date
      travel_to(Date.new(2018,10,7))
      renew_all(0)
      travel_to(Date.new(2018,12,9))
      issue2, issue3 = renew_all(2)
      assert_equal Date.new(2018,11,5), issue2.start_date
      assert_equal Date.new(2018,11,10), issue2.due_date
      assert_equal Date.new(2018,12,10), issue3.start_date
      assert_equal Date.new(2018,12,15), issue3.due_date
      travel_to(Date.new(2018,12,10))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_monthly_wday_from_first
    log_user 'alice', 'foo'
    @issue1.start_date = Date.new(2018,10,1)
    @issue1.due_date = Date.new(2018,10,3)
    @issue1.save!

    [:first_issue_fixed, :last_issue_fixed].each do |am|
      travel_to(Date.new(2018,4,1))
      create_recurrence(anchor_mode: am,
                        mode: :monthly_wday_from_first,
                        multiplier: 1)
      renew_all(0)
      travel_to(Date.new(2018,6,1))
      renew_all(0)
      travel_to(Date.new(2018,10,1))
      issue1 = renew_all(1).first
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
    @issue1.start_date = Date.new(2018,9,26)
    @issue1.due_date = Date.new(2018,9,28)
    @issue1.save!

    [:first_issue_fixed, :last_issue_fixed].each do |am|
      travel_to(Date.new(2018,3,26))
      create_recurrence(anchor_mode: am,
                        mode: :monthly_wday_to_last,
                        multiplier: 2)
      renew_all(0)
      travel_to(Date.new(2018,5,26))
      renew_all(0)
      travel_to(Date.new(2018,9,26))
      issue1 = renew_all(1).first
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
    @issue1.start_date = Date.new(2018,8,19)
    @issue1.due_date = Date.new(2018,9,5)
    @issue1.save!

    [:first_issue_fixed, :last_issue_fixed].each do |am|
      travel_to(Date.new(2017,8,2))
      create_recurrence(anchor_mode: am,
                        mode: :yearly,
                        multiplier: 1)
      renew_all(0)
      travel_to(Date.new(2018,8,18))
      renew_all(0)
      travel_to(Date.new(2018,8,19))
      issue1 = renew_all(1).first
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
    @issue1.start_date = Date.new(2018,10,1)
    @issue1.due_date = Date.new(2018,10,5)
    @issue1.save!

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
    issue1 = renew_all(1).first
    assert_equal Date.new(2018,10,13), issue1.start_date
    assert_equal Date.new(2018,10,17), issue1.due_date
    travel_to(Date.new(2018,10,15))
    renew_all(0)
    # closed between start and due
    close_issue(issue1)
    issue2 = renew_all(1).first
    assert_equal Date.new(2018,10,21), issue2.start_date
    assert_equal Date.new(2018,10,25), issue2.due_date
    travel_to(Date.new(2018,10,19))
    renew_all(0)
    # closed before start
    close_issue(issue2)
    travel_to(Date.new(2018,10,22))
    issue3 = renew_all(1).first
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
    @issue1.start_date = Date.new(2018,10,1)
    @issue1.due_date = Date.new(2018,10,5)
    @issue1.save!

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
    issue1 = renew_all(1).first
    assert_equal Date.new(2018,10,13), issue1.start_date
    assert_equal Date.new(2018,10,17), issue1.due_date
    travel_to(Date.new(2018,10,15))
    renew_all(0)
    # closed between start and due
    close_issue(issue1)
    issue2 = renew_all(1).first
    assert_equal Date.new(2018,10,23), issue2.start_date
    assert_equal Date.new(2018,10,27), issue2.due_date
    travel_to(Date.new(2018,10,21))
    renew_all(0)
    # closed before start
    close_issue(issue2)
    travel_to(Date.new(2018,10,25))
    issue3 = renew_all(1).first
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
    @issue1.start_date = Date.new(2018,9,25)
    @issue1.due_date = Date.new(2018,10,4)
    @issue1.save!

    items = {
      daily: [Date.new(2021,6,21), Date.new(2021,6,30)],
      weekly: [Date.new(2037,11,24), Date.new(2037,12,3)],
      monthly_day_from_first: [Date.new(2102,1,25), Date.new(2102,2,4)],
      monthly_day_to_last: [Date.new(2102,1,26), Date.new(2102,2,1)],
      monthly_dow_from_first: [Date.new(2102,1,24), Date.new(2102,2,2)],
      monthly_dow_to_last: [Date.new(2102,1,31), Date.new(2102,2,2)],
      monthly_wday_from_first: [Date.new(2102,1,24), Date.new(2102,2,6)],
      monthly_wday_to_last: [Date.new(2102,1,26), Date.new(2102,2,1)],
      yearly: [Date.new(3018,9,25), Date.new(3018,10,4)],
    }
    items.each do |m, (start, due)|
      travel_to(Date.new(2018,10,21))
      create_recurrence(anchor_mode: :last_issue_fixed,
                        mode: m,
                        multiplier: 1000)
      issue1 = renew_all(1).first
      assert_equal start, issue1.start_date
      assert_equal due, issue1.due_date
    end
  end

  def test_renew_closed_on_cleared_for_new_recurrences_of_closed_issue
    log_user 'alice', 'foo'
    @issue1.start_date = Date.new(2018,9,25)
    @issue1.due_date = Date.new(2018,10,4)
    @issue1.save!

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
    @issue1.start_date = Date.new(2018,8,20)
    @issue1.due_date = Date.new(2019,1,10)
    @issue1.save!

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

    [:first_issue_fixed, :last_issue_fixed].each do |am|
      dates.each do |issue_dates, setup_dates|
        @issue1.start_date = issue_dates[:start]
        @issue1.due_date = issue_dates[:due]
        @issue1.save!

        create_recurrence(anchor_mode: am,
                          mode: :monthly_dow_from_first,
                          multiplier: 1)

        setup_dates.each do |t, r_dates|
          travel_to(t)
          r = renew_all(r_dates.present? ? 1 : 0)
          if r_dates.present?
            if r_dates[:start].present?
              assert_equal r_dates[:start], r.first.start_date
            else
              assert_nil r.first.start_date
            end
            if r_dates[:due].present?
              assert_equal r_dates[:due], r.first.due_date
            else
              assert_nil r.first.due_date
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
      @issue1.start_date = issue_dates[:start]
      @issue1.due_date = issue_dates[:due]
      @issue1.save!
      assert_nil @issue1.closed_on

      ir = create_recurrence(anchor_mode: :last_issue_flexible,
                             mode: :monthly_dow_from_first,
                             multiplier: 1)

      setup_dates.each do |t, close, r_dates|
        travel_to(t)
        close_issue(ir.last_issue || @issue1) if close
        ir.reload
        r = renew_all(r_dates.present? ? 1 : 0)
        if r_dates.present?
          if r_dates[:start].present?
            assert_equal r_dates[:start], r.first.start_date
          else
            assert_nil r.first.start_date
          end
          if r_dates[:due].present?
            assert_equal r_dates[:due], r.first.due_date
          else
            assert_nil r.first.due_date
          end
        end
      end
    end
  end

  # TODO:
  # - issue without start/due/both dates
  # - first_issue_fixed monthly with date > 28 recurring through February
  # - monthly_dow with same dow (2nd Tuesday+2nd Thursday) + month when 1st
  # Thursday is before 1st Tuesaday (start date ater than end date)
  # - monthly_dow when there is 5th day of week in one month but not in
  # subsequent (and generally all recurrences that yield overflow)
  # - first_issue_fixed with date movement forward/backward on issue and last
  # recurrence
  # - renew_all with and without as_user
  # - tests of creation modes
end

