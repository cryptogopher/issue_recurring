require File.expand_path('../../test_helper', __FILE__)

class IssueRecurrencesTest < IssueRecurringIntegrationTestCase
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

  def test_create_recurrence
    @issue1.update!(due_date: Date.new(2018, 10, 1))
    create_recurrence
  end

  def test_create_anchor_modes_when_issue_dates_not_set
    @issue1.update!(start_date: nil, due_date: nil)

    # params, blank_dates_allowed?
    anchor_modes = [
      {anchor_mode: :first_issue_fixed}, false,
      {anchor_mode: :last_issue_fixed}, false,
      {anchor_mode: :last_issue_flexible}, true,
      {anchor_mode: :last_issue_flexible_on_delay}, true,
      {anchor_mode: :last_issue_fixed_after_close}, false,
      {anchor_mode: :date_fixed_after_close, creation_mode: :in_place,
       anchor_date: Date.current}, true
    ]

    anchor_modes.each_slice(2) do |params, blank_dates_allowed|
      if blank_dates_allowed
        create_recurrence(params)
      else
        errors = create_recurrence_should_fail(params)
        assert errors.added?(:anchor_mode, :issue_anchor_no_blank_dates)
      end
    end
  end

  def test_create_anchor_to_start_set_to_nil_date_when_other_date_set_should_fail
    @issue1.update!(start_date: Date.current, due_date: nil)
    errors = create_recurrence_should_fail(anchor_to_start: false)
    assert errors.added?(:anchor_to_start, :due_mode_requires_date)

    @issue1.update!(start_date: nil, due_date: Date.current)
    errors = create_recurrence_should_fail(anchor_to_start: true)
    assert errors.added?(:anchor_to_start, :start_mode_requires_date)
  end

  def test_create_anchor_modes_with_creation_mode_in_place
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    # params, in_place_allowed?
    anchor_modes = [
      {anchor_mode: :first_issue_fixed}, false,
      {anchor_mode: :last_issue_fixed}, false,
      {anchor_mode: :last_issue_flexible}, true,
      {anchor_mode: :last_issue_flexible_on_delay}, true,
      {anchor_mode: :last_issue_fixed_after_close}, true,
      {anchor_mode: :date_fixed_after_close, anchor_date: Date.current}, true
    ]

    anchor_modes.each_slice(2) do |params, in_place_allowed|
      params.update(creation_mode: :in_place)
      if in_place_allowed
        r = create_recurrence(params)
        destroy_recurrence(r)
      else
        errors = create_recurrence_should_fail(params)
        assert errors.added?(:anchor_mode,
                             errors.generate_message(:anchor_mode, :in_place_closed_only))
      end
    end
  end

  def test_create_multiple_creation_mode_in_place_if_not_date_fixed_should_fail
    # issue: https://it.michalczyk.pro/issues/14
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    anchor_modes = [
      {anchor_mode: :last_issue_flexible}, false,
      {anchor_mode: :last_issue_flexible_on_delay}, false,
      {anchor_mode: :last_issue_fixed_after_close}, false,
      {anchor_mode: :date_fixed_after_close, anchor_date: Date.current}, true
    ]
    anchor_modes.each_slice(2) do |first_params, first_allow_multiple|
      first_params.update(creation_mode: :in_place)
      r1st = create_recurrence(first_params)

      anchor_modes.each_slice(2) do |second_params, second_allow_multiple|
        second_params.update(creation_mode: :in_place)
        if first_allow_multiple || second_allow_multiple
          r2nd = create_recurrence(second_params)
          destroy_recurrence(r2nd)
        else
          errors = create_recurrence_should_fail(second_params)
          assert errors.added?(:creation_mode,
                               errors.generate_message(:creation_mode, :only_one_in_place))
        end
      end

      destroy_recurrence(r1st)
    end
  end

  def test_create_anchor_modes_with_delay
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    # params, delay_allowed?
    anchor_modes = [
      {anchor_mode: :first_issue_fixed}, true,
      {anchor_mode: :last_issue_fixed}, true,
      {anchor_mode: :last_issue_flexible}, false,
      {anchor_mode: :last_issue_flexible_on_delay}, false,
      {anchor_mode: :last_issue_fixed_after_close}, true,
      {anchor_mode: :date_fixed_after_close, creation_mode: :in_place,
       anchor_date: Date.current}, true
    ]
    anchor_modes.each_slice(2) do |params, delay_allowed|
      params.update(anchor_to_start: true,
                    mode: :monthly_day_from_first,
                    delay_mode: :day,
                    delay_multiplier: 10)
      if delay_allowed
        create_recurrence(params)
      else
        errors = create_recurrence_should_fail(params)
        assert errors.added?(:anchor_mode,
                             errors.generate_message(:anchor_mode, :close_anchor_no_delay))
      end
    end
  end

  def test_create_multiple_recurrences
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    IssueRecurrence::creation_modes.each do |creation_mode|
      IssueRecurrence::anchor_modes.each do |anchor_mode|
        params = {creation_mode: creation_mode, anchor_mode: anchor_mode}
        params.update(anchor_date: Date.current) if anchor_mode == 'date_fixed_after_close'

        r = create_recurrence(params)
        # only one in-place allowed
        destroy_recurrence(r) if creation_mode == 'in_place'
      end
    end
  end

  def test_create_only_when_manage_permission_granted
    logout_user
    log_user 'bob', 'foo'
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    roles = users(:bob).members.find_by(project: @issue1.project_id).roles
    assert roles.any? { |role| role.has_permission? :manage_issue_recurrences }
    create_recurrence

    roles.each { |role| role.remove_permission! :manage_issue_recurrences }
    refute roles.any? { |role| role.has_permission? :manage_issue_recurrences }
    create_recurrence_should_fail(error_code: :forbidden)
  end

  def test_destroy_only_when_manage_permission_granted
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))
    recurrence = create_recurrence
    logout_user

    log_user 'bob', 'foo'
    roles = users(:bob).members.find_by(project: @issue1.project_id).roles

    roles.each { |role| role.remove_permission! :manage_issue_recurrences }
    refute roles.any? { |role| role.has_permission? :manage_issue_recurrences }
    destroy_recurrence_should_fail(recurrence, error_code: :forbidden)

    roles.each { |role| role.add_permission! :manage_issue_recurrences }
    assert roles.any? { |role| role.has_permission? :manage_issue_recurrences }
    destroy_recurrence(recurrence)
  end

  def test_show_issue_shows_recurrences_only_when_view_permission_granted
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))
    create_recurrence
    logout_user

    roles = users(:bob).members.find_by(project: @issue1.project_id).roles
    assert roles.any? { |role| role.has_permission? :view_issue_recurrences }

    log_user 'bob', 'foo'
    get issue_path(@issue1)
    assert_response :ok
    assert_select 'div#issue_recurrences'

    roles.each { |role| role.remove_permission! :view_issue_recurrences }
    refute roles.any? { |role| role.has_permission? :view_issue_recurrences }

    get issue_path(@issue1)
    assert_response :ok
    assert_select 'div#issue_recurrences', false
  end

  def test_show_issue_shows_recurrence_form_only_when_manage_permission_granted
    logout_user
    log_user 'bob', 'foo'

    roles = users(:bob).members.find_by(project: @issue1.project_id).roles
    assert roles.any? { |role| role.has_permission? :manage_issue_recurrences }
    get issue_path(@issue1)
    assert_response :ok
    assert_select 'form#new-recurrence-form'

    roles.each { |role| role.remove_permission! :manage_issue_recurrences }
    refute roles.any? { |role| role.has_permission? :manage_issue_recurrences }
    get issue_path(@issue1)
    assert_response :ok
    assert_select 'form#new-recurrence-form', false
  end

  def test_show_plugin_settings
    User.current.admin = true
    User.current.save!

    get plugin_settings_path('issue_recurring')
    assert_response :ok
  end

  def test_index_and_project_view_tab_visible_only_when_view_permission_granted
    logout_user
    log_user 'bob', 'foo'

    roles = users(:bob).members.find_by(project: @issue1.project_id).roles
    assert roles.any? { |role| role.has_permission? :view_issue_recurrences }
    get project_recurrences_path(projects(:project_01))
    assert_response :ok
    assert_select 'div#main-menu ul li a.issue-recurrences'

    roles.each { |role| role.remove_permission! :view_issue_recurrences }
    refute roles.any? { |role| role.has_permission? :view_issue_recurrences }
    get project_recurrences_path(projects(:project_01))
    assert_response :forbidden
    assert_select 'div#main-menu ul li a.issue-recurrences', false
  end

  def test_renew_anchor_mode_fixed_mode_daily
    @issue1.update!(start_date: Date.new(2018,10,1), due_date: Date.new(2018,10,5))

    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      travel_to(Date.new(2018,9,21))
      create_recurrence(anchor_mode: anchor_mode,
                        mode: :daily,
                        multiplier: 10)
      renew_all(0)
      travel_to(Date.new(2018,9,30))
      renew_all(0)
      travel_to(Date.new(2018,10,1))
      r1 = renew_all(1)
      assert_equal Date.new(2018,10,11), r1.start_date
      assert_equal Date.new(2018,10,15), r1.due_date
      travel_to(Date.new(2018,10,9))
      renew_all(0)
      travel_to(Date.new(2018,10,30))
      r2, r3 = renew_all(2)
      assert_equal Date.new(2018,10,21), r2.start_date
      assert_equal Date.new(2018,10,25), r2.due_date
      assert_equal Date.new(2018,10,31), r3.start_date
      assert_equal Date.new(2018,11,4), r3.due_date
      travel_to(Date.new(2018,10,31))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_daily_wday
    @issue1.update!(start_date: Date.new(2018,9,13), due_date: Date.new(2018,10,2))

    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      travel_to(Date.new(2018,8,12))
      create_recurrence(anchor_mode: anchor_mode,
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
    @issue1.update!(start_date: Date.new(2018,8,12), due_date: Date.new(2018,8,20))

    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      travel_to(Date.new(2018,7,29))
      create_recurrence(anchor_mode: anchor_mode,
                        mode: :weekly,
                        multiplier: 4)
      renew_all(0)
      travel_to(Date.new(2018,8,12))
      r1 = renew_all(1)
      assert_equal Date.new(2018,9,9), r1.start_date
      assert_equal Date.new(2018,9,17), r1.due_date
      travel_to(Date.new(2018,9,8))
      renew_all(0)
      travel_to(Date.new(2018,11,3))
      r2, r3 = renew_all(2)
      assert_equal Date.new(2018,10,7), r2.start_date
      assert_equal Date.new(2018,10,15), r2.due_date
      assert_equal Date.new(2018,11,4), r3.start_date
      assert_equal Date.new(2018,11,12), r3.due_date
      travel_to(Date.new(2018,11,4))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_monthly_day_from_first
    @issue1.update!(start_date: Date.new(2018,9,8), due_date: Date.new(2018,10,2))

    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      travel_to(Date.new(2017,9,8))
      create_recurrence(anchor_mode: anchor_mode,
                        anchor_to_start: true,
                        mode: :monthly_day_from_first,
                        multiplier: 2)
      renew_all(0)
      travel_to(Date.new(2017,1,8))
      renew_all(0)
      travel_to(Date.new(2018,9,8))
      r1 = renew_all(1)
      assert_equal Date.new(2018,11,8), r1.start_date
      assert_equal Date.new(2018,12,2), r1.due_date
      travel_to(Date.new(2018,11,7))
      renew_all(0)
      travel_to(Date.new(2019,3,7))
      r2, r3 = renew_all(2)
      assert_equal Date.new(2019,1,8), r2.start_date
      assert_equal Date.new(2019,2,1), r2.due_date
      assert_equal Date.new(2019,3,8), r3.start_date
      assert_equal Date.new(2019,4,1), r3.due_date
      travel_to(Date.new(2019,3,8))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_monthly_day_to_last
    @issue1.update!(start_date: Date.new(2018,9,22), due_date: Date.new(2018,10,10))

    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      travel_to(Date.new(2018,3,22))
      create_recurrence(anchor_mode: anchor_mode,
                        mode: :monthly_day_to_last,
                        multiplier: 3)
      renew_all(0)
      travel_to(Date.new(2018,5,21))
      renew_all(0)
      travel_to(Date.new(2018,9,22))
      r1 = renew_all(1)
      assert_equal Date.new(2018,12,23), r1.start_date
      assert_equal Date.new(2019,1,10), r1.due_date
      travel_to(Date.new(2018,12,22))
      renew_all(0)
      travel_to(Date.new(2019,6,21))
      r2, r3 = renew_all(2)
      assert_equal Date.new(2019,3,22), r2.start_date
      assert_equal Date.new(2019,4,9), r2.due_date
      assert_equal Date.new(2019,6,22), r3.start_date
      assert_equal Date.new(2019,7,10), r3.due_date
      travel_to(Date.new(2019,6,22))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_monthly_dow_from_first
    @issue1.update!(start_date: Date.new(2018,9,22), due_date: Date.new(2018,10,10))

    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      travel_to(Date.new(2018,3,22))
      create_recurrence(anchor_mode: anchor_mode,
                        anchor_to_start: true,
                        mode: :monthly_dow_from_first,
                        multiplier: 2)
      renew_all(0)
      travel_to(Date.new(2018,5,21))
      renew_all(0)
      travel_to(Date.new(2018,9,22))
      r1 = renew_all(1)
      assert_equal Date.new(2018,11,24), r1.start_date
      assert_equal Date.new(2018,12,12), r1.due_date
      travel_to(Date.new(2018,11,22))
      renew_all(0)
      travel_to(Date.new(2019,3,22))
      r2, r3 = renew_all(2)
      assert_equal Date.new(2019,1,26), r2.start_date
      assert_equal Date.new(2019,2,13), r2.due_date
      assert_equal Date.new(2019,3,23), r3.start_date
      assert_equal Date.new(2019,4,10), r3.due_date
      travel_to(Date.new(2019,3,23))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_monthly_dow_to_last
    @issue1.update!(start_date: Date.new(2018,9,3), due_date: Date.new(2018,9,15))

    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      travel_to(Date.new(2018,6,3))
      create_recurrence(anchor_mode: anchor_mode,
                        mode: :monthly_dow_to_last,
                        multiplier: 1)
      renew_all(0)
      travel_to(Date.new(2018,8,3))
      renew_all(0)
      travel_to(Date.new(2018,9,3))
      r1 = renew_all(1)
      assert_equal Date.new(2018,10,1), r1.start_date
      assert_equal Date.new(2018,10,13), r1.due_date
      travel_to(Date.new(2018,9,30))
      renew_all(0)
      travel_to(Date.new(2018,12,2))
      r2, r3 = renew_all(2)
      assert_equal Date.new(2018,10,29), r2.start_date
      assert_equal Date.new(2018,11,10), r2.due_date
      assert_equal Date.new(2018,12,3), r3.start_date
      assert_equal Date.new(2018,12,15), r3.due_date
      travel_to(Date.new(2018,12,3))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_monthly_wday_from_first
    @issue1.update!(start_date: Date.new(2018,10,1), due_date: Date.new(2018,10,3))

    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      travel_to(Date.new(2018,4,1))
      create_recurrence(anchor_mode: anchor_mode,
                        mode: :monthly_wday_from_first,
                        multiplier: 1)
      renew_all(0)
      travel_to(Date.new(2018,6,1))
      renew_all(0)
      travel_to(Date.new(2018,10,1))
      r1 = renew_all(1)
      assert_equal Date.new(2018,11,1), r1.start_date
      assert_equal Date.new(2018,11,5), r1.due_date
      travel_to(Date.new(2018,10,31))
      renew_all(0)
      travel_to(Date.new(2018,12,31))
      r2, r3 = renew_all(2)
      assert_equal Date.new(2018,12,3), r2.start_date
      assert_equal Date.new(2018,12,5), r2.due_date
      assert_equal Date.new(2019,1,1), r3.start_date
      assert_equal Date.new(2019,1,3), r3.due_date
      travel_to(Date.new(2019,1,1))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_monthly_wday_to_last
    @issue1.update!(start_date: Date.new(2018,9,26), due_date: Date.new(2018,9,28))

    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      travel_to(Date.new(2018,3,26))
      create_recurrence(anchor_mode: anchor_mode,
                        anchor_to_start: true,
                        mode: :monthly_wday_to_last,
                        multiplier: 2)
      renew_all(0)
      travel_to(Date.new(2018,5,26))
      renew_all(0)
      travel_to(Date.new(2018,9,26))
      r1 = renew_all(1)
      assert_equal Date.new(2018,11,28), r1.start_date
      assert_equal Date.new(2018,11,30), r1.due_date
      travel_to(Date.new(2018,11,27))
      renew_all(0)
      travel_to(Date.new(2019,3,26))
      r2, r3 = renew_all(2)
      assert_equal Date.new(2019,1,29), r2.start_date
      assert_equal Date.new(2019,1,31), r2.due_date
      assert_equal Date.new(2019,3,27), r3.start_date
      assert_equal Date.new(2019,3,29), r3.due_date
      travel_to(Date.new(2019,3,27))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_fixed_mode_yearly
    @issue1.update!(start_date: Date.new(2018,8,19), due_date: Date.new(2018,9,5))

    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      travel_to(Date.new(2017,8,2))
      create_recurrence(anchor_mode: anchor_mode,
                        mode: :yearly,
                        multiplier: 1)
      renew_all(0)
      travel_to(Date.new(2018,8,18))
      renew_all(0)
      travel_to(Date.new(2018,8,19))
      r1 = renew_all(1)
      assert_equal Date.new(2019,8,19), r1.start_date
      assert_equal Date.new(2019,9,5), r1.due_date
      travel_to(Date.new(2019,8,18))
      renew_all(0)
      travel_to(Date.new(2021,8,18))
      r2, r3 = renew_all(2)
      assert_equal Date.new(2020,8,19), r2.start_date
      assert_equal Date.new(2020,9,5), r2.due_date
      assert_equal Date.new(2021,8,19), r3.start_date
      assert_equal Date.new(2021,9,5), r3.due_date
      travel_to(Date.new(2021,8,20))
      renew_all(1)
      renew_all(0)
    end
  end

  def test_renew_anchor_mode_flexible_mode_daily
    @issue1.update!(start_date: Date.new(2018,10,1), due_date: Date.new(2018,10,5))

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
    r1 = renew_all(1)
    assert_equal Date.new(2018,10,13), r1.start_date
    assert_equal Date.new(2018,10,17), r1.due_date
    travel_to(Date.new(2018,10,15))
    renew_all(0)
    # closed between start and due
    close_issue(r1)
    r2 = renew_all(1)
    assert_equal Date.new(2018,10,21), r2.start_date
    assert_equal Date.new(2018,10,25), r2.due_date
    travel_to(Date.new(2018,10,19))
    renew_all(0)
    # closed before start
    close_issue(r2)
    travel_to(Date.new(2018,10,22))
    r3 = renew_all(1)
    assert_equal Date.new(2018,10,25), r3.start_date
    assert_equal Date.new(2018,10,29), r3.due_date
    travel_to(Date.new(2018,11,18))
    close_issue(r3)
    travel_to(Date.new(2018,12,31))
    renew_all(1)
    renew_all(0)
  end

  def test_renew_anchor_mode_flexible_on_delay_mode_daily
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
    r1 = renew_all(1)
    assert_equal Date.new(2018,10,13), r1.start_date
    assert_equal Date.new(2018,10,17), r1.due_date
    travel_to(Date.new(2018,10,15))
    renew_all(0)
    # closed between start and due
    close_issue(r1)
    r2 = renew_all(1)
    assert_equal Date.new(2018,10,23), r2.start_date
    assert_equal Date.new(2018,10,27), r2.due_date
    travel_to(Date.new(2018,10,21))
    renew_all(0)
    # closed before start
    close_issue(r2)
    travel_to(Date.new(2018,10,25))
    r3 = renew_all(1)
    assert_equal Date.new(2018,11,2), r3.start_date
    assert_equal Date.new(2018,11,6), r3.due_date
    travel_to(Date.new(2018,11,18))
    close_issue(r3)
    travel_to(Date.new(2018,12,31))
    renew_all(1)
    renew_all(0)
  end

  def test_renew_anchor_mode_fixed_after_close_mode_weekly
    @issue1.update!(start_date: Date.new(2019,7,5), due_date: Date.new(2019,7,10))

    travel_to(Date.new(2019,7,1))
    create_recurrence(anchor_mode: :last_issue_fixed_after_close,
                      mode: :weekly,
                      multiplier: 2)
    renew_all(0)
    travel_to(Date.new(2019,7,13))
    renew_all(0)
    # closed after due, before recurrence period
    close_issue(@issue1)
    r1 = renew_all(1)
    assert_equal Date.new(2019,7,19), r1.start_date
    assert_equal Date.new(2019,7,24), r1.due_date
    travel_to(Date.new(2019,7,21))
    renew_all(0)
    # closed between start and due
    close_issue(r1)
    r2 = renew_all(1)
    assert_equal Date.new(2019,8,2), r2.start_date
    assert_equal Date.new(2019,8,7), r2.due_date
    travel_to(Date.new(2019,8,1))
    renew_all(0)
    # closed before start
    close_issue(r2)
    r3 = renew_all(1)
    assert_equal Date.new(2019,8,16), r3.start_date
    assert_equal Date.new(2019,8,21), r3.due_date
    travel_to(Date.new(2019,9,18))
    # closed after due, after 2 full recurrence periods + few days
    close_issue(r3)
    r4 = renew_all(1)
    assert_equal Date.new(2019,9,27), r4.start_date
    assert_equal Date.new(2019,10,2), r4.due_date

    travel_to(Date.new(2019,11,30))
    close_issue(r4)
    travel_to(Date.new(2019,12,31))
    renew_all(1)
    renew_all(0)
  end

  def test_renew_anchor_mode_date_fixed_after_close_mode_weekly
    @issue1.update!(start_date: Date.new(2019,7,8), due_date: Date.new(2019,7,13))

    travel_to(Date.new(2019,7,1))
    create_recurrence(anchor_mode: :date_fixed_after_close,
                      anchor_to_start: true,
                      mode: :weekly,
                      multiplier: 2,
                      creation_mode: :in_place,
                      anchor_date: Date.new(2019,7,5))
    renew_all(0)
    @issue1.reload
    assert_equal Date.new(2019,7,8), @issue1.start_date
    assert_equal Date.new(2019,7,13), @issue1.due_date

    travel_to(Date.new(2019,7,14))
    renew_all(0)
    @issue1.reload
    assert_equal Date.new(2019,7,8), @issue1.start_date
    assert_equal Date.new(2019,7,13), @issue1.due_date
    # closed after due, before recurrence period
    close_issue(@issue1)
    renew_all(0)
    @issue1.reload
    assert_equal Date.new(2019,7,19), @issue1.start_date
    assert_equal Date.new(2019,7,24), @issue1.due_date

    travel_to(Date.new(2019,7,18))
    renew_all(0)
    @issue1.reload
    assert_equal Date.new(2019,7,19), @issue1.start_date
    assert_equal Date.new(2019,7,24), @issue1.due_date
    # closed before start
    close_issue(@issue1)
    renew_all(0)
    @issue1.reload
    assert_equal Date.new(2019,8,2), @issue1.start_date
    assert_equal Date.new(2019,8,7), @issue1.due_date

    travel_to(Date.new(2019,7,27))
    renew_all(0)
    @issue1.reload
    assert_equal Date.new(2019,8,2), @issue1.start_date
    assert_equal Date.new(2019,8,7), @issue1.due_date
    # closed before anchor date multiple
    close_issue(@issue1)
    renew_all(0)
    @issue1.reload
    assert_equal Date.new(2019,8,16), @issue1.start_date
    assert_equal Date.new(2019,8,21), @issue1.due_date

    travel_to(Date.new(2019,9,18))
    renew_all(0)
    @issue1.reload
    assert_equal Date.new(2019,8,16), @issue1.start_date
    assert_equal Date.new(2019,8,21), @issue1.due_date
    # closed after due, after 2 full recurrence periods + few days
    close_issue(@issue1)
    renew_all(0)
    @issue1.reload
    assert_equal Date.new(2019,9,27), @issue1.start_date
    assert_equal Date.new(2019,10,2), @issue1.due_date
  end

  def test_renew_huge_multiplier
    @issue1.update!(start_date: Date.new(2018,9,25), due_date: Date.new(2018,10,4))

    configs = [
      :daily, true, Date.new(2021,6,21), Date.new(2021,6,30),
      :weekly, false, Date.new(2037,11,24), Date.new(2037,12,3),
      :monthly_day_from_first, true, Date.new(2102,1,25), Date.new(2102,2,3),
      :monthly_day_from_first, false, Date.new(2102,1,26), Date.new(2102,2,4),
      :monthly_day_to_last, true, Date.new(2102,1,26), Date.new(2102,2,4),
      :monthly_day_to_last, false, Date.new(2102,1,23), Date.new(2102,2,1),
      :monthly_dow_from_first, true, Date.new(2102,1,24), Date.new(2102,2,2),
      :monthly_dow_from_first, false, Date.new(2102,1,24), Date.new(2102,2,2),
      :monthly_dow_to_last, true, Date.new(2102,1,31), Date.new(2102,2,9),
      :monthly_dow_to_last, false, Date.new(2102,1,24), Date.new(2102,2,2),
      :monthly_wday_from_first, true, Date.new(2102,1,24), Date.new(2102,2,2),
      :monthly_wday_from_first, false, Date.new(2102,1,26), Date.new(2102,2,6),
      :monthly_wday_to_last, true, Date.new(2102,1,26), Date.new(2102,2,6),
      :monthly_wday_to_last, false, Date.new(2102,1,23), Date.new(2102,2,1),
      :yearly, true, Date.new(3018,9,25), Date.new(3018,10,4),
    ]
    configs.each_slice(4) do |mode, anchor_to_start, start_date, due_date|
      travel_to(Date.new(2018,10,21))
      create_recurrence(anchor_mode: :last_issue_fixed,
                        anchor_to_start: anchor_to_start,
                        mode: mode,
                        multiplier: 1000)
      r1 = renew_all(1)
      assert_equal start_date, r1.start_date
      assert_equal due_date, r1.due_date
    end
  end

  def test_renew_new_recurrences_of_closed_issue_should_not_be_closed
    IssueRecurrence::creation_modes.each do |creation_mode|
      @issue1.update!(start_date: Date.new(2018,9,25), due_date: Date.new(2018,10,4))
      # Issue can be open and have not nil closed_on time if it has been
      # closed+reopened in the past.
      # Issue status should be checked by closed?, not closed_on.
      assert !@issue1.closed?

      travel_to(Date.new(2018,10,4))
      r = create_recurrence(anchor_mode: :last_issue_flexible,
                            creation_mode: creation_mode,
                            mode: :weekly,
                            multiplier: 2)

      close_issue(@issue1)
      assert @issue1.reload.closed?
      r1 = renew_all(1)
      assert !r1.closed?

      destroy_recurrence(r)
      reopen_issue(@issue1)
      @issue1.reload
    end
  end

  def test_renew_creation_mode_in_place_if_issue_not_closed_should_not_recur
    anchor_modes = [
      {anchor_mode: :last_issue_flexible},
      {anchor_mode: :last_issue_flexible_on_delay},
      {anchor_mode: :last_issue_fixed_after_close},
      {anchor_mode: :date_fixed_after_close, anchor_date: Date.new(2018,11,12)},
    ]

    anchor_modes.each do |r_params|
      @issue1.update!(start_date: Date.new(2018,9,15),
                      due_date: Date.new(2018,9,20),
                      closed_on: nil)
      r = create_recurrence(r_params.update(creation_mode: :in_place))
      travel_to(Date.new(2018,11,12))

      assert_equal 0, r.count
      assert !@issue1.closed?
      assert_nil @issue1.closed_on
      renew_all(0)
      assert 0, r.reload.count
      assert !@issue1.reload.closed?

      # closed_on set to non-nil value while issue status is not closed should
      # not cause recurrence as well.
      @issue1.update!(closed_on: Date.new(2018,9,17))
      assert !@issue1.closed?
      assert_not_nil @issue1.closed_on
      renew_all(0)
      assert 0, r.reload.count
      assert !@issue1.reload.closed?

      assert_equal Date.new(2018,9,15), @issue1.start_date
      assert_equal Date.new(2018,9,20), @issue1.due_date

      close_issue(@issue1)
      assert @issue1.reload.closed?
      renew_all(0)
      assert 1, r.reload.count
      assert !@issue1.reload.closed?

      destroy_recurrence(r)
    end
  end

  def test_renew_issue_with_timespan_much_larger_than_recurrence_period
    @issue1.update!(start_date: Date.new(2018,8,20), due_date: Date.new(2019,1,10))

    create_recurrence(anchor_mode: :last_issue_fixed,
                      mode: :daily,
                      multiplier: 3)
    travel_to(Date.new(2018,9,1))
    *, r5 = renew_all(5)
    assert_equal Date.new(2018,9,4), r5.start_date
    assert_equal Date.new(2019,1,25), r5.due_date
  end

  def test_renew_anchor_mode_fixed_one_issue_date_not_set
    configs = [
      {start_date: Date.new(2018,10,10), due_date: nil},
      [
        [Date.new(2018,10,9), nil],
        [Date.new(2018,10,10), {start: Date.new(2018,11,14), due: nil}],
        [Date.new(2018,11,13), nil],
        [Date.new(2018,11,14), {start: Date.new(2018,12,12), due: nil}]
      ],
      {start_date: nil, due_date: Date.new(2018,10,15)},
      [
        [Date.new(2018,10,14), nil],
        [Date.new(2018,10,15), {start: nil, due: Date.new(2018,11,19)}],
        [Date.new(2018,11,18), nil],
        [Date.new(2018,11,19), {start: nil, due: Date.new(2018,12,17)}]
      ]
    ]

    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      configs.each_slice(2) do |issue_dates, recurrence_dates|
        @issue1.reload
        @issue1.update!(issue_dates)

        anchor_to_start = issue_dates[:start_date].present? ? true : false
        create_recurrence(anchor_mode: anchor_mode,
                          anchor_to_start: anchor_to_start,
                          mode: :monthly_dow_from_first,
                          multiplier: 1)

        recurrence_dates.each do |travel, dates|
          travel_to(travel)
          r = renew_all(dates.present? ? 1 : 0)
          if dates.present?
            if dates[:start].present?
              assert_equal dates[:start], r.start_date
            else
              assert_nil r.start_date
            end
            if dates[:due].present?
              assert_equal dates[:due], r.due_date
            else
              assert_nil r.due_date
            end
          end
        end
      end
    end
  end

  def process_close_based_recurrences(configs, creation_modes)
    creation_modes.each do |creation_mode|
      configs.each_slice(3) do |issue_dates, r_params, r_details|
        @issue1.reload
        @issue1.update!(issue_dates)
        reopen_issue(@issue1) if @issue1.closed?

        r = create_recurrence(r_params.update(creation_mode: creation_mode))

        r_details.each_slice(3) do |travel_close, travel_renew, r_dates|
          r.reload
          if travel_close
            travel_to(travel_close) if travel_close
            close_issue(r.last_issue || @issue1)
          end
          travel_to(travel_renew)
          r1 = if r.creation_mode == 'in_place'
                 renew_all(0)
                 @issue1.reload
               else
                 renew_all(r_dates.present? ? 1 : 0)
               end
          if r_dates.present?
            if r_dates[:start].present?
              assert_equal r_dates[:start], r1.start_date
            else
              assert_nil r1.start_date
            end
            if r_dates[:due].present?
              assert_equal r_dates[:due], r1.due_date
            else
              assert_nil r1.due_date
            end
          end
        end

        destroy_recurrence(r)
      end
    end
  end

  def test_renew_anchor_mode_last_issue_flexible_issue_dates_set_and_unset
    configs = [
      # last_issue_flexible, both dates set
      {start_date: Date.new(2018,9,13), due_date: Date.new(2018,10,2)},
      {anchor_mode: :last_issue_flexible, mode: :monthly_day_from_first,
       anchor_to_start: true},
      [
        Date.new(2018,9,15), Date.new(2018,11,4),
          {start: Date.new(2018,10,15), due: Date.new(2018,11,3)},
        Date.new(2018,11,15), Date.new(2018,11,16),
         {start: Date.new(2018,12,15), due: Date.new(2019,1,3)},
      ],

      # last_issue_flexible, only one date set
      {start_date: Date.new(2018,10,10), due_date: nil},
      {anchor_mode: :last_issue_flexible, mode: :monthly_dow_from_first,
       anchor_to_start: true},
      [
        nil, Date.new(2018,10,12), nil,
        Date.new(2018,10,15), Date.new(2018,10,15), {start: Date.new(2018,11,19), due: nil},
        nil, Date.new(2018,11,25), nil,
        Date.new(2018,11,30), Date.new(2018,11,30), {start: Date.new(2018,12,28), due: nil}
      ],
      {start_date: nil, due_date: Date.new(2018,10,15)},
      {anchor_mode: :last_issue_flexible, mode: :monthly_dow_from_first,
       anchor_to_start: false},
      [
        nil, Date.new(2018,10,19), nil,
        Date.new(2018,10,26), Date.new(2018,10,26), {start: nil, due: Date.new(2018,11,23)},
        nil, Date.new(2018,12,6), nil,
        Date.new(2018,12,8), Date.new(2018,12,8), {start: nil, due: Date.new(2019,1,12)}
      ],

      # last_issue_flexible, both dates unset
      {start_date: nil, due_date: nil},
      {anchor_mode: :last_issue_flexible, mode: :weekly, anchor_to_start: true},
      [
        nil, Date.new(2018,10,12), nil,
        Date.new(2018,10,15), Date.new(2018,10,15), {start: Date.new(2018,10,22), due: nil},
      ],
      {start_date: nil, due_date: nil},
      {anchor_mode: :last_issue_flexible, mode: :weekly, anchor_to_start: false},
      [
        nil, Date.new(2018,10,12), nil,
        Date.new(2018,10,15), Date.new(2018,10,15), {start: nil, due: Date.new(2018,10,22)},
        nil, Date.new(2018,11,25), nil,
        Date.new(2018,11,30), Date.new(2018,11,30), {start: nil, due: Date.new(2018,12,7)}
      ]
    ]

    process_close_based_recurrences(configs, [:copy_first, :in_place])
  end

  def test_renew_anchor_mode_last_issue_flexible_on_delay_with_issue_dates_set_and_unset
    configs = [
      # last_issue_flexible_on_delay, both dates set
      {start_date: Date.new(2018,9,13), due_date: Date.new(2018,10,2)},
      {anchor_mode: :last_issue_flexible_on_delay, mode: :monthly_day_from_first,
       anchor_to_start: true},
      [
        Date.new(2018,9,10), Date.new(2018,9,12),
          {start: Date.new(2018,10,13), due: Date.new(2018,11,1)},
        Date.new(2018,10,15), Date.new(2018,10,24),
          {start: Date.new(2018,11,13), due: Date.new(2018,12,2)},
        Date.new(2018,12,15), Date.new(2018,12,15),
         {start: Date.new(2019,1,15), due: Date.new(2019,2,3)},
      ],

      # last_issue_flexible_on_delay, only one date set
      {start_date: Date.new(2018,10,10), due_date: nil},
      {anchor_mode: :last_issue_flexible_on_delay, mode: :monthly_dow_from_first,
       anchor_to_start: true},
      [
        nil, Date.new(2018,10,9), nil,
        Date.new(2018,10,9), Date.new(2018,10,9), {start: Date.new(2018,11,14), due: nil},
        nil, Date.new(2018,11,13), nil,
        Date.new(2018,11,14), Date.new(2018,11,20), {start: Date.new(2018,12,12), due: nil},
        nil, Date.new(2018,12,25), nil,
        Date.new(2018,12,30), Date.new(2018,12,30), {start: Date.new(2019,1,27), due: nil}
      ],
      {start_date: nil, due_date: Date.new(2018,10,15)},
      {anchor_mode: :last_issue_flexible_on_delay, mode: :monthly_dow_from_first,
       anchor_to_start: false},
      [
        nil, Date.new(2018,10,10), nil,
        Date.new(2018,10,13), Date.new(2018,10,13), {start: nil, due: Date.new(2018,11,19)},
        nil, Date.new(2018,12,20), nil,
        Date.new(2018,12,20), Date.new(2018,12,28), {start: nil, due: Date.new(2019,1,17)}
      ],

      # last_issue_flexible_on_delay, both dates unset - same as last_issue_flexible
      {start_date: nil, due_date: nil},
      {anchor_mode: :last_issue_flexible_on_delay, mode: :weekly, anchor_to_start: true},
      [
        nil, Date.new(2018,10,12), nil,
        Date.new(2018,10,15), Date.new(2018,10,15), {start: Date.new(2018,10,22), due: nil},
      ],
      {start_date: nil, due_date: nil},
      {anchor_mode: :last_issue_flexible_on_delay, mode: :weekly, anchor_to_start: false},
      [
        nil, Date.new(2018,10,12), nil,
        Date.new(2018,10,15), Date.new(2018,10,15), {start: nil, due: Date.new(2018,10,22)},
        nil, Date.new(2018,11,25), nil,
        Date.new(2018,11,30), Date.new(2018,11,30), {start: nil, due: Date.new(2018,12,7)}
      ]
    ]

    process_close_based_recurrences(configs, [:copy_first, :in_place])
  end

  def test_renew_anchor_mode_last_issue_fixed_after_close_with_issue_dates_set_and_unset
    configs = [
      # last_issue_fixed_after_close, both dates set
      {start_date: Date.new(2018,9,13), due_date: Date.new(2018,10,2)},
      {anchor_mode: :last_issue_fixed_after_close, mode: :monthly_day_from_first,
       anchor_to_start: true},
      [
        Date.new(2018,9,15), Date.new(2018,11,4),
          {start: Date.new(2018,10,13), due: Date.new(2018,11,1)},
        Date.new(2019,1,15), Date.new(2018,1,15),
         {start: Date.new(2019,2,13), due: Date.new(2019,3,4)},
        Date.new(2019,2,12), Date.new(2018,2,12),
         {start: Date.new(2019,3,13), due: Date.new(2019,4,1)},
      ],

      # last_issue_fixed_after_close, only one date set
      {start_date: Date.new(2018,10,10), due_date: nil},
      {anchor_mode: :last_issue_fixed_after_close, mode: :monthly_dow_from_first,
       anchor_to_start: true},
      [
        nil, Date.new(2018,10,9), nil,
        Date.new(2018,10,9), Date.new(2018,10,9), {start: Date.new(2018,11,14), due: nil},
        Date.new(2018,12,30), Date.new(2018,12,31), {start: Date.new(2019,1,9), due: nil},
        nil, Date.new(2019,3,25), nil,
        Date.new(2019,3,30), Date.new(2019,3,30), {start: Date.new(2019,4,10), due: nil}
      ],
      {start_date: nil, due_date: Date.new(2018,10,15)},
      {anchor_mode: :last_issue_fixed_after_close, mode: :monthly_dow_from_first,
       anchor_to_start: false},
      [
        Date.new(2019,2,17), Date.new(2019,2,17), {start: nil, due: Date.new(2019,2,18)},
        nil, Date.new(2019,2,18), nil,
        Date.new(2019,4,15), Date.new(2019,4,15), {start: nil, due: Date.new(2019,5,20)}
      ]

      # last_issue_fixed_after_close, both dates unset disallowed
    ]

    process_close_based_recurrences(configs, [:copy_first, :in_place])
  end

  def test_renew_anchor_mode_date_fixed_after_close_with_issue_dates_set_and_unset
    configs = [
      # date_fixed_after_close, both dates set
      {start_date: Date.new(2018,9,13), due_date: Date.new(2018,10,2)},
      {anchor_mode: :date_fixed_after_close, mode: :monthly_day_from_first,
       anchor_to_start: true, creation_mode: :in_place, anchor_date: Date.new(2018,9,5)},
      [
        Date.new(2018,12,15), Date.new(2018,12,24),
          {start: Date.new(2019,1,5), due: Date.new(2019,1,24)},
        Date.new(2019,1,4), Date.new(2018,1,4),
         {start: Date.new(2019,2,5), due: Date.new(2019,2,24)},
      ],

      # date_fixed_after_close, only one date set
      {start_date: Date.new(2018,10,10), due_date: nil},
      {anchor_mode: :date_fixed_after_close, mode: :monthly_dow_from_first,
       anchor_to_start: true, creation_mode: :in_place, anchor_date: Date.new(2018,11,5)},
      [
        nil, Date.new(2018,12,9), nil,
        Date.new(2019,1,9), Date.new(2019,1,9), {start: Date.new(2019,2,4), due: nil},
        Date.new(2019,2,3), Date.new(2019,2,4), {start: Date.new(2019,3,4), due: nil},
      ],
      {start_date: nil, due_date: Date.new(2018,10,15)},
      {anchor_mode: :date_fixed_after_close, mode: :monthly_dow_to_last,
       anchor_to_start: false, creation_mode: :in_place, anchor_date: Date.new(2018,12,31)},
      [
        Date.new(2018,12,30), Date.new(2018,12,30), {start: nil, due: Date.new(2018,12,31)},
        Date.new(2019,2,17), Date.new(2019,2,17), {start: nil, due: Date.new(2019,2,25)},
        nil, Date.new(2019,2,18), nil,
        Date.new(2019,2,25), Date.new(2019,2,25), {start: nil, due: Date.new(2019,3,25)}
      ],

      # date_fixed_after_close, both dates unset
      {start_date: nil, due_date: nil},
      {anchor_mode: :date_fixed_after_close, mode: :weekly,
       anchor_to_start: true, creation_mode: :in_place, anchor_date: Date.new(2019,6,7)},
      [
        nil, Date.new(2019,7,17), nil,
        Date.new(2019,7,18), Date.new(2019,7,18), {start: Date.new(2019,7,19), due: nil},
      ],
      {start_date: nil, due_date: nil},
      {anchor_mode: :date_fixed_after_close, mode: :weekly,
       anchor_to_start: false, creation_mode: :in_place, anchor_date: Date.new(2019,6,7)},
      [
        nil, Date.new(2019,7,17), nil,
        Date.new(2019,7,18), Date.new(2019,7,18), {start: nil, due: Date.new(2019,7,19)},
        Date.new(2019,7,26), Date.new(2019,7,26), {start: nil, due: Date.new(2019,8,2)}
      ]
    ]

    process_close_based_recurrences(configs, [:in_place])
  end

  def test_renew_anchor_mode_flexible_anchor_to_start_varies
    configs = [
      {start_date: Date.new(2019,4,25), due_date: Date.new(2019,5,3)},
      {anchor_mode: :last_issue_flexible, anchor_to_start: true},
      Date.new(2019,4,29),
      {start: Date.new(2019,5,29), due: Date.new(2019,6,6)},

      {start_date: Date.new(2019,4,25), due_date: Date.new(2019,5,3)},
      {anchor_mode: :last_issue_flexible, anchor_to_start: false},
      Date.new(2019,5,6),
      {start: Date.new(2019,5,29), due: Date.new(2019,6,6)},

      {start_date: Date.new(2019,4,25), due_date: Date.new(2019,5,3)},
      {anchor_mode: :last_issue_flexible_on_delay, anchor_to_start: true},
      Date.new(2019,5,1),
      {start: Date.new(2019,5,25), due: Date.new(2019,6,2)},

      {start_date: Date.new(2019,4,25), due_date: Date.new(2019,5,3)},
      {anchor_mode: :last_issue_flexible_on_delay, anchor_to_start: false},
      Date.new(2019,5,1),
      {start: Date.new(2019,5,26), due: Date.new(2019,6,3)},

      {start_date: Date.new(2019,4,25), due_date: Date.new(2019,5,3)},
      {anchor_mode: :last_issue_flexible_on_delay, anchor_to_start: true},
      Date.new(2019,5,26),
      {start: Date.new(2019,6,26), due: Date.new(2019,7,4)},

      {start_date: Date.new(2019,4,25), due_date: Date.new(2019,5,3)},
      {anchor_mode: :last_issue_flexible_on_delay, anchor_to_start: false},
      Date.new(2019,5,6),
      {start: Date.new(2019,5,29), due: Date.new(2019,6,6)},
    ]

    configs.each_slice(4) do |issue_dates, r_params, close_date, r_dates|
      @issue1.update!(issue_dates)
      reopen_issue(@issue1) if @issue1.closed?

      r = create_recurrence(r_params.update(mode: :monthly_day_from_first))

      travel_to(close_date)
      close_issue(@issue1)
      r1 = renew_all(1)
      assert_equal r_dates[:start], r1.start_date
      assert_equal r_dates[:due], r1.due_date

      destroy_recurrence(r)
    end
  end

  def test_renew_mode_monthly_should_not_overflow_in_shorter_month
    configs = [
      {start_date: Date.new(2019,1,29), due_date: Date.new(2019,1,31)},
      {anchor_to_start: true, mode: :monthly_day_from_first},
      {start: Date.new(2019,2,28), due: Date.new(2019,3,2)},

      {start_date: Date.new(2019,1,29), due_date: Date.new(2019,1,31)},
      {anchor_to_start: false, mode: :monthly_day_from_first},
      {start: Date.new(2019,2,26), due: Date.new(2019,2,28)},

      {start_date: Date.new(2019,1,1), due_date: Date.new(2019,1,3)},
      {anchor_to_start: true, mode: :monthly_day_to_last},
      {start: Date.new(2019,2,1), due: Date.new(2019,2,3)},

      {start_date: Date.new(2019,1,1), due_date: Date.new(2019,1,3)},
      {anchor_to_start: false, mode: :monthly_day_to_last},
      {start: Date.new(2019,1,30), due: Date.new(2019,2,1)},

      {start_date: Date.new(2019,1,29), due_date: Date.new(2019,1,31)},
      {anchor_to_start: true, mode: :monthly_dow_from_first},
      {start: Date.new(2019,2,26), due: Date.new(2019,2,28)},

      {start_date: Date.new(2019,1,29), due_date: Date.new(2019,1,31)},
      {anchor_to_start: false, mode: :monthly_dow_from_first},
      {start: Date.new(2019,2,26), due: Date.new(2019,2,28)},

      {start_date: Date.new(2019,1,1), due_date: Date.new(2019,1,3)},
      {anchor_to_start: true, mode: :monthly_dow_to_last},
      {start: Date.new(2019,2,5), due: Date.new(2019,2,7)},

      {start_date: Date.new(2019,1,1), due_date: Date.new(2019,1,3)},
      {anchor_to_start: false, mode: :monthly_dow_to_last},
      {start: Date.new(2019,2,5), due: Date.new(2019,2,7)},

      {start_date: Date.new(2019,1,29), due_date: Date.new(2019,1,31)},
      {anchor_to_start: true, mode: :monthly_wday_from_first},
      {start: Date.new(2019,2,28), due: Date.new(2019,3,4)},

      {start_date: Date.new(2019,1,29), due_date: Date.new(2019,1,31)},
      {anchor_to_start: false, mode: :monthly_wday_from_first},
      {start: Date.new(2019,2,26), due: Date.new(2019,2,28)},

      {start_date: Date.new(2019,1,1), due_date: Date.new(2019,1,3)},
      {anchor_to_start: true, mode: :monthly_wday_to_last},
      {start: Date.new(2019,2,1), due: Date.new(2019,2,5)},

      {start_date: Date.new(2019,1,1), due_date: Date.new(2019,1,3)},
      {anchor_to_start: false, mode: :monthly_wday_to_last},
      {start: Date.new(2019,1,30), due: Date.new(2019,2,1)},
    ]

    configs.each_slice(3) do |issue_dates, r_params, r_dates|
      travel_to(issue_dates[:start_date])
      @issue1.update!(issue_dates)

      r = create_recurrence(r_params)

      r1 = renew_all(1)
      assert_equal r_dates[:start], r1.start_date
      assert_equal r_dates[:due], r1.due_date
    end
  end

  def test_renew_mode_yearly_should_honor_anchor_to_start_during_leap_year
    configs = [
      {start_date: Date.new(2019,2,20), due_date: Date.new(2019,3,10)},
      {anchor_to_start: true},
      {start: Date.new(2020,2,20), due: Date.new(2020,3,9)},

      {start_date: Date.new(2019,2,20), due_date: Date.new(2019,3,10)},
      {anchor_to_start: false},
      {start: Date.new(2020,2,21), due: Date.new(2020,3,10)},
    ]

    configs.each_slice(3) do |issue_dates, r_params, r_dates|
      travel_to(issue_dates[:start_date])
      @issue1.update!(issue_dates)

      ir = create_recurrence(r_params.update(mode: :yearly))

      r = renew_all(1)
      assert_equal r_dates[:start], r.start_date
      assert_equal r_dates[:due], r.due_date
    end
  end

  def test_renew_anchor_mode_fixed_with_delay
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      travel_to(Date.new(2018,9,14))
      create_recurrence(anchor_mode: anchor_mode,
                        anchor_to_start: true,
                        mode: :monthly_day_from_first,
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

  def test_renew_sets_recurrence_of_for_new_recurrence_and_subtask
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

  def test_renew_subtasks
    configs = [
      {start_date: Date.new(2018,9,25), due_date: Date.new(2018,10,5)},
      {start_date: Date.new(2018,9,20), due_date: Date.new(2018,9,30)},
      {mode: :weekly},
      {start: Date.new(2018,9,27), due: Date.new(2018,10,12)},
      {start: Date.new(2018,10,2), due: Date.new(2018,10,12)},
      {start: Date.new(2018,9,27), due: Date.new(2018,10,7)},

      {start_date: Date.new(2018,9,25), due_date: Date.new(2018,10,5)},
      {start_date: Date.new(2018,9,20), due_date: Date.new(2018,9,30)},
      {mode: :monthly_dow_from_first, anchor_to_start: true},
      {start: Date.new(2018,10,18), due: Date.new(2018,11,2)},
      {start: Date.new(2018,10,23), due: Date.new(2018,11,2)},
      {start: Date.new(2018,10,18), due: Date.new(2018,10,28)},

      {start_date: Date.new(2018,9,25), due_date: Date.new(2018,10,5)},
      {start_date: Date.new(2018,9,20), due_date: Date.new(2018,9,30)},
      {mode: :monthly_wday_to_last, anchor_to_start: false},
      {start: Date.new(2018,10,22), due: Date.new(2018,11,6)},
      {start: Date.new(2018,10,25), due: Date.new(2018,11,6)},
      {start: Date.new(2018,10,22), due: Date.new(2018,10,31)},
    ]

    set_parent_issue(@issue1, @issue2)
    set_parent_issue(@issue1, @issue3)

    configs.each_slice(6) do |issue2_dates, issue3_dates, r_params,
                              r1_dates, r2_dates, r3_dates|
      @issue2.update!(issue2_dates)
      @issue3.update!(issue3_dates)
      @issue1.reload

      create_recurrence(r_params.update(include_subtasks: true))
      travel_to(@issue1.start_date-1)
      renew_all(0)

      travel_to(@issue1.start_date)
      r1, * = renew_all(3)
      assert_equal r1_dates[:start], r1.start_date
      assert_equal r1_dates[:due], r1.due_date

      r2 = IssueRelation.where(issue_from: @issue2, relation_type: 'copied_to').last.issue_to
      assert_equal r2_dates[:start], r2.start_date
      assert_equal r2_dates[:due], r2.due_date

      r3 = IssueRelation.where(issue_from: @issue3, relation_type: 'copied_to').last.issue_to
      assert_equal r3_dates[:start], r3.start_date
      assert_equal r3_dates[:due], r3.due_date
    end
  end

  def test_renew_creation_mode_copy_first
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
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    r = create_recurrence(creation_mode: :in_place, anchor_mode: :last_issue_flexible)
    travel_to(Date.new(2018,9,18))
    renew_all(0)
    @issue1.reload
    assert_equal Date.new(2018,9,15), @issue1.start_date
    r.reload
    assert_nil r.last_issue

    close_issue(@issue1)
    renew_all(0)
    @issue1.reload
    assert_equal Date.new(2018,9,20), @issue1.start_date
    assert_equal Date.new(2018,9,25), @issue1.due_date
    assert !@issue1.closed?
    r.reload
    assert_equal r.last_issue, @issue1
  end

  def test_renew_applies_author_id_configuration_setting
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

  def test_renew_anchor_mode_date_fixed_after_close_after_issue_date_change
    @issue1.update!(start_date: Date.new(2019,7,18), due_date: Date.new(2019,7,22))

    create_recurrence(anchor_mode: :date_fixed_after_close, anchor_date: Date.new(2019,7,8),
                      anchor_to_start: true, creation_mode: :in_place,
                      mode: :daily_wday, multiplier: 10)

    travel_to(Date.new(2019,7,18))
    close_issue(@issue1)
    renew_all(0)
    assert !@issue1.reload.closed?
    assert_equal Date.new(2019,7,22), @issue1.start_date
    assert_equal Date.new(2019,7,24), @issue1.due_date

    # only dates changed, same timespan
    @issue1.update!(start_date: Date.new(2019,6,19), due_date: Date.new(2019,6,21))
    travel_to(Date.new(2019,8,5))
    close_issue(@issue1)
    renew_all(0)
    assert !@issue1.reload.closed?
    assert_equal Date.new(2019,8,19), @issue1.start_date
    assert_equal Date.new(2019,8,21), @issue1.due_date

    # changed both dates and timespan
    @issue1.update!(start_date: Date.new(2019,7,1), due_date: Date.new(2019,7,10))
    travel_to(Date.new(2019,9,1))
    close_issue(@issue1)
    renew_all(0)
    assert !@issue1.reload.closed?
    assert_equal Date.new(2019,9,2), @issue1.start_date
    assert_equal Date.new(2019,9,11), @issue1.due_date
  end

  def test_renew_multiple_anchor_mode_date_fixed_after_close_with_additional_in_place
    @issue1.update!(start_date: Date.new(2019,7,12), due_date: Date.new(2019,7,13))

    # Recur every 15th and last day of month, but not less often than every 10 days.
    create_recurrence(anchor_mode: :date_fixed_after_close,
                     anchor_to_start: true,
                     anchor_date: Date.new(2019,6,30),
                     mode: :monthly_day_to_last,
                     multiplier: 1,
                     creation_mode: :in_place)
    create_recurrence(anchor_mode: :date_fixed_after_close,
                     anchor_to_start: true,
                     anchor_date: Date.new(2019,6,15),
                     mode: :monthly_day_from_first,
                     multiplier: 1,
                     creation_mode: :in_place)
    create_recurrence(anchor_mode: :last_issue_flexible,
                     anchor_to_start: true,
                     mode: :daily,
                     multiplier: 10,
                     creation_mode: :in_place)

    dates = [
      Date.new(2019,7,14), {start: Date.new(2019,7,15), due: Date.new(2019,7,16)},
      Date.new(2019,7,15), {start: Date.new(2019,7,25), due: Date.new(2019,7,26)},
      Date.new(2019,7,29), {start: Date.new(2019,7,31), due: Date.new(2019,8,1)},
      Date.new(2019,8,22), {start: Date.new(2019,8,31), due: Date.new(2019,9,1)},
      Date.new(2019,9,2), {start: Date.new(2019,9,12), due: Date.new(2019,9,13)},
      Date.new(2019,9,8), {start: Date.new(2019,9,15), due: Date.new(2019,9,16)}
    ]

    dates.each_slice(2) do |close_date, r_dates|
      travel_to(close_date)
      close_issue(@issue1)
      renew_all(0)
      @issue1.reload
      assert_equal r_dates[:start], @issue1.start_date
      assert_equal r_dates[:due], @issue1.due_date
    end
  end

  def test_renew_anchor_mode_fixed_after_dates_removed_should_log_error
    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

      ir = create_recurrence(anchor_mode: anchor_mode)
      travel_to(Date.new(2018,9,15))
      r1 = renew_all(1)

      ref_issue = (anchor_mode == :first_issue_fixed) ? @issue1 : r1
      ref_issue.update!(start_date: nil, due_date: nil)
      travel_to(Date.new(2018,11,22))
      assert_difference 'Journal.count', 1 do
        renew_all(0)
      end
      assert Journal.last.notes.include?('both dates (start and due) are blank')
      @issue1.reload

      destroy_recurrence(ir)
    end
  end

  def test_renew_anchor_mode_fixed_after_anchor_date_removed_should_log_error
    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      @issue1.update!(start_date: Date.new(2018,9,15), due_date: nil)
      ir = create_recurrence(anchor_mode: anchor_mode,
                        anchor_to_start: true,
                        mode: :monthly_day_from_first)
      travel_to(Date.new(2018,9,15))
      r1 = renew_all(1)

      ref_issue = (anchor_mode == :first_issue_fixed) ? @issue1 : r1
      ref_issue.update!(start_date: nil, due_date: Date.new(2018,9,20))
      travel_to(Date.new(2018,12,22))
      assert_difference 'Journal.count', 1 do
        renew_all(0)
      end
      assert Journal.last.notes.include?('created for issue without start date')
      @issue1.reload

      destroy_recurrence(ir)


      @issue1.update!(start_date: nil, due_date: Date.new(2018,9,20))
      ir = create_recurrence(anchor_mode: anchor_mode,
                        anchor_to_start: false,
                        mode: :monthly_day_from_first)
      travel_to(Date.new(2018,9,20))
      r1 = renew_all(1)
      @issue1.reload

      ref_issue = (anchor_mode == :first_issue_fixed) ? @issue1 : r1
      ref_issue.update!(start_date: Date.new(2018,9,15), due_date: nil)
      travel_to(Date.new(2018,12,22))
      assert_difference 'Journal.count', 1 do
        renew_all(0)
      end
      assert Journal.last.notes.include?('created for issue without due date')

      destroy_recurrence(ir)
    end
  end

  def test_deleting_first_issue_destroys_recurrence_and_nullifies_recurrence_of
    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      @issue1 = Issue.first
      @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

      recurrence = create_recurrence(@issue1, anchor_mode: anchor_mode)
      travel_to(Date.new(2018,9,22))
      r1, r2 = renew_all(2)

      assert_difference 'IssueRecurrence.count', -1 do
        destroy_issue(@issue1)
      end
      assert_raises(ActiveRecord::RecordNotFound) { recurrence.reload }

      [r1, r2].map(&:reload)
      assert_nil r1.recurrence_of
      assert_nil r2.recurrence_of
    end
  end

  def test_deleting_last_issue_sets_previous_or_nullifies_last_issue
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      recurrence = create_recurrence(anchor_mode: anchor_mode)
      travel_to(Date.new(2018,9,22))
      r1, r2 = renew_all(2)
      recurrence.reload
      assert_equal r2, recurrence.last_issue

      # Create extra recurrences with higher ids
      @issue2.update!(start_date: Date.new(2018,8,15), due_date: Date.new(2018,8,20))
      create_recurrence(@issue2, anchor_mode: anchor_mode)
      renew_all(6)

      assert_no_difference 'IssueRecurrence.count' do
        destroy_issue(r2)
      end
      [recurrence, r1].map(&:reload)
      assert_equal r1, recurrence.last_issue

      assert_no_difference 'IssueRecurrence.count' do
        destroy_issue(r1)
      end
      recurrence.reload
      assert_nil recurrence.last_issue
    end
  end

  def test_deleting_not_first_nor_last_issue_keeps_recurrence_and_reference_of_unchanged
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    [:first_issue_fixed, :last_issue_fixed].each do |anchor_mode|
      recurrence = create_recurrence(anchor_mode: anchor_mode)
      travel_to(Date.new(2018,9,22))
      r1, r2 = renew_all(2)

      assert_no_difference 'IssueRecurrence.count' do
        destroy_issue(r1)
      end
      [recurrence, r2].map(&:reload)
      assert_equal recurrence.last_issue, r2
      assert_equal recurrence.issue, r2.recurrence_of
    end
  end
end
