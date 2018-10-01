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

  def test_renew_all
    log_user 'alice', 'foo'
    @issue1.start_date = Date.new(2018, 10, 1)
    @issue1.due_date = Date.new(2018, 10, 5)
    travel_to(@issue.start_date)

    setups = [
      [{is_fixed_schedule: true, creation_mode: :copy_first, mode: :daily,
        mode_multiplier: 10},
       9.days,
       []],
      [{is_fixed_schedule: true, creation_mode: :copy_first, mode: :daily,
        mode_multiplier: 10},
       10.days,
       [['2018-10-11', '2018-10-15'], ]],
    ]

    setups.each do |recurrence_attrs, t, dates|
      create_recurrence(recurrence_attrs)
      travel(t)
      renew_all(count=dates.length)
      dates.each do |start_date, due_date|
        Issue.find_by!(start_date: start_date, end_date: end_date)
      end
    end
  end
end
