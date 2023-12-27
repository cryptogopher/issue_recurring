require_relative '../test_helper'

class IssueRecurrencesTest < IssueRecurringIntegrationTestCase
  def setup
    super

    Setting.non_working_week_days = [6, 7]
    Setting.parent_issue_dates = 'derived'
    Setting.parent_issue_priority = 'derived'
    Setting.parent_issue_done_ratio = 'derived'
    Setting.issue_done_ratio == 'issue_field'

    log_user 'admin', 'foo'
    update_plugin_settings(author_id: 0,
                           keep_assignee: false,
                           journal_mode: :never,
                           copy_recurrences: true,
                           ahead_multiplier: 0,
                           ahead_mode: :days)
    logout_user

    @project1 = projects(:project_01)
    @issue1 = issues(:issue_01)
    @issue2 = issues(:issue_02)
    @issue3 = issues(:issue_03)

    log_user 'alice', 'foo'
  end

  def teardown
    super
    logout_user
  end

  def test_create_anchor_modes_when_issue_dates_not_set
    @issue1.update!(start_date: nil, due_date: nil)

    # params, blank dates allowed?
    anchor_modes = [
      {anchor_mode: :first_issue_fixed}, false,
      {anchor_mode: :last_issue_fixed}, false,
      {anchor_mode: :last_issue_flexible}, true,
      {anchor_mode: :last_issue_flexible_on_delay}, true,
      {anchor_mode: :last_issue_fixed_after_close}, false,
      {anchor_mode: :date_fixed_after_close, anchor_date: Date.current}, true
    ]

    anchor_modes.each_slice(2) do |params, blank_dates_allowed|
      if blank_dates_allowed
        create_recurrence(**params)
      else
        errors = create_recurrence_should_fail(**params)
        assert errors.added?(:anchor_mode, :blank_issue_dates_require_reopen)
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

  def test_create_anchor_modes_with_creation_mode_reopen
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    # params, reopen allowed?
    anchor_modes = [
      {anchor_mode: :first_issue_fixed}, false,
      {anchor_mode: :last_issue_fixed}, false,
      {anchor_mode: :last_issue_flexible}, true,
      {anchor_mode: :last_issue_flexible_on_delay}, true,
      {anchor_mode: :last_issue_fixed_after_close}, true,
      {anchor_mode: :date_fixed_after_close, anchor_date: Date.current}, true
    ]

    anchor_modes.each_slice(2) do |params, reopen_allowed|
      params.update(creation_mode: :reopen)
      if reopen_allowed
        r = create_recurrence(**params)
        destroy_recurrence(r)
      else
        errors = create_recurrence_should_fail(**params)
        assert errors.added?(:anchor_mode,
                 errors.generate_message(:anchor_mode, :reopen_requires_close_date_based))
      end
    end
  end

  def test_create_multiple_creation_mode_reopen_if_not_date_fixed_should_fail
    # issue: https://it.michalczyk.pro/issues/14
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    # params, multiple reopen allowed?
    anchor_modes = [
      {anchor_mode: :last_issue_flexible}, false,
      {anchor_mode: :last_issue_flexible_on_delay}, false,
      {anchor_mode: :last_issue_fixed_after_close}, false,
      {anchor_mode: :date_fixed_after_close, anchor_date: Date.current}, true
    ]
    anchor_modes.each_slice(2) do |first_params, first_allow_multiple|
      first_params.update(creation_mode: :reopen)
      r1st = create_recurrence(**first_params)

      anchor_modes.each_slice(2) do |second_params, second_allow_multiple|
        second_params.update(creation_mode: :reopen)
        if first_allow_multiple || second_allow_multiple
          r2nd = create_recurrence(**second_params)
          destroy_recurrence(r2nd)
        else
          errors = create_recurrence_should_fail(**second_params)
          assert errors.added?(:creation_mode,
                               errors.generate_message(:creation_mode, :only_one_reopen))
        end
      end

      destroy_recurrence(r1st)
    end
  end

  def test_create_anchor_modes_with_delay
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    # params, delay allowed?
    anchor_modes = [
      {anchor_mode: :first_issue_fixed}, true,
      {anchor_mode: :last_issue_fixed}, true,
      {anchor_mode: :last_issue_flexible}, false,
      {anchor_mode: :last_issue_flexible_on_delay}, false,
      {anchor_mode: :last_issue_fixed_after_close}, true,
      {anchor_mode: :date_fixed_after_close, anchor_date: Date.current}, true
    ]
    anchor_modes.each_slice(2) do |params, delay_allowed|
      params.update(anchor_to_start: true,
                    mode: :monthly_day_from_first,
                    delay_mode: :days,
                    delay_multiplier: 10)
      if delay_allowed
        create_recurrence(**params)
      else
        errors = create_recurrence_should_fail(**params)
        assert errors.added?(:anchor_mode,
                 errors.generate_message(:anchor_mode, :delay_requires_fixed_anchor))
      end
    end
  end

  def test_create_date_limit_before_anchor_date_should_fail
    @issue1.update!(random_dates)
    anchor_date = random_date
    errors = create_recurrence_should_fail(anchor_mode: :date_fixed_after_close,
                                           anchor_date: anchor_date,
                                           date_limit: anchor_date)
    assert errors.added?(:date_limit, :not_after_anchor_date)
  end

  # TODO: should be based on random sample pairs [creation_mode, anchor_mode]
  # of random length
  def test_create_multiple_recurrences
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    IssueRecurrence::creation_modes.each_key do |creation_mode|
      IssueRecurrence::anchor_modes.each_key do |anchor_mode|
        params = {creation_mode: creation_mode, anchor_mode: anchor_mode}
        case anchor_mode
        when 'first_issue_fixed', 'last_issue_fixed'
          next if creation_mode == 'reopen'
        when 'date_fixed_after_close'
          params[:anchor_date] = Date.current
        end

        r = create_recurrence(**params)
        # multiple reopen allowed only for :date_fixed_after_close
        if (creation_mode == 'reopen') && (anchor_mode != 'date_fixed_after_close')
          destroy_recurrence(r)
        end
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

  def test_create_creation_mode_reopen_without_subtasks_if_dates_derived_should_fail
    set_parent_issue(@issue1, @issue2)
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))
    @issue2.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    Setting.parent_issue_dates = 'derived'
    errors = create_recurrence_should_fail(
      anchor_mode: :last_issue_flexible,
      creation_mode: :reopen,
      include_subtasks: false
    )
    assert errors.added?(
      :creation_mode,
      errors.generate_message(:creation_mode, :derived_dates_reopen_requires_subtasks)
    )

    Setting.parent_issue_dates = 'independent'
    r = create_recurrence(
      anchor_mode: :last_issue_flexible,
      creation_mode: :reopen,
      include_subtasks: false
    )
    destroy_recurrence(r)

    Setting.parent_issue_dates = 'derived'
    r = create_recurrence(
      anchor_mode: :last_issue_flexible,
      creation_mode: :reopen,
      include_subtasks: true
    )
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

  def test_show_plugin_settings
    User.find(session[:user_id]).update!(admin: true)

    get plugin_settings_path('issue_recurring')
    assert_response :ok
  end

  def test_show_issue_shows_next_and_predicted_dates
    # issue dates, recurrence params, check date, {close?: recurrence dates}
    configs = [
      # fixed with single 'next'
      {start_date: Date.new(2019,8,6), due_date: Date.new(2019,8,7)},
      [
        {anchor_mode: :first_issue_fixed, anchor_to_start: false,
         mode: :monthly_day_from_first, multiplier: 1}
      ],
      Date.new(2019,8,14),
      {
        false => [
          {next: ["2019-09-06 - 2019-09-07"], predicted: ["2019-10-06 - 2019-10-07"]}
        ]
      },

      # fixed with multiple 'next' without and with date/count limits
      {start_date: Date.new(2019,8,6), due_date: Date.new(2019,8,7)},
      [
        {anchor_mode: :last_issue_fixed, anchor_to_start: true,
         mode: :weekly, multiplier: 1},
        {anchor_mode: :last_issue_fixed, anchor_to_start: true,
         mode: :weekly, multiplier: 1, count_limit: 2},
        {anchor_mode: :last_issue_fixed, anchor_to_start: true,
         mode: :weekly, multiplier: 1, count_limit: 3},
        {anchor_mode: :last_issue_fixed, anchor_to_start: true,
         mode: :weekly, multiplier: 1, count_limit: 5},
        {anchor_mode: :last_issue_fixed, anchor_to_start: true,
         mode: :weekly, multiplier: 1, date_limit: Date.new(2019,8,15)},
        {anchor_mode: :last_issue_fixed, anchor_to_start: true,
         mode: :weekly, multiplier: 1, date_limit: Date.new(2019,9,1)},
        {anchor_mode: :last_issue_fixed, anchor_to_start: true,
         mode: :weekly, multiplier: 1, date_limit: Date.new(2019,10,1)}
      ],
      Date.new(2019,8,22),
      {
        false => [
          {next: ["2019-08-13 - 2019-08-14", "2019-08-20 - 2019-08-21",
                  "2019-08-27 - 2019-08-28"],
           predicted: ["2019-09-03 - 2019-09-04"]},
          {next: ["2019-08-13 - 2019-08-14", "2019-08-20 - 2019-08-21"],
           predicted: ["-"]},
          {next: ["2019-08-13 - 2019-08-14", "2019-08-20 - 2019-08-21",
                  "2019-08-27 - 2019-08-28"],
           predicted: ["-"]},
          {next: ["2019-08-13 - 2019-08-14", "2019-08-20 - 2019-08-21",
                  "2019-08-27 - 2019-08-28"],
           predicted: ["2019-09-03 - 2019-09-04"]},
          {next: ["2019-08-13 - 2019-08-14"],
           predicted: ["-"]},
          {next: ["2019-08-13 - 2019-08-14", "2019-08-20 - 2019-08-21",
                  "2019-08-27 - 2019-08-28"],
           predicted: ["-"]},
          {next: ["2019-08-13 - 2019-08-14", "2019-08-20 - 2019-08-21",
                  "2019-08-27 - 2019-08-28"],
           predicted: ["2019-09-03 - 2019-09-04"]}
        ]
      },

      # close based
      {start_date: Date.new(2019,8,6), due_date: Date.new(2019,8,7)},
      [
        {anchor_mode: :last_issue_flexible, anchor_to_start: false,
         mode: :yearly, multiplier: 1}
      ],
      Date.new(2019,8,22),
      {
        false => [
          {next: ["-"], predicted: ["2020-08-21 - 2020-08-22"]}
        ],
        true => [
          {next: ["2020-08-21 - 2020-08-22"], predicted: ["-"]}
        ]
      },

      # multiple reopens
      {start_date: Date.new(2019,8,6), due_date: Date.new(2019,8,7)},
      [
        {anchor_mode: :last_issue_fixed_after_close, anchor_to_start: true,
         mode: :monthly_wday_from_first, multiplier: 1,
         creation_mode: :reopen},
        {anchor_mode: :date_fixed_after_close, anchor_to_start: true,
         mode: :monthly_wday_from_first, multiplier: 1,
         creation_mode: :reopen, anchor_date: Date.new(2019,8,1)},
        {anchor_mode: :date_fixed_after_close, anchor_to_start: true,
         mode: :monthly_wday_from_first, multiplier: 1,
         creation_mode: :reopen, anchor_date: Date.new(2019,8,10)}
      ],
      Date.new(2019,8,22),
      {
        false => [
          {next: ["-"], predicted: ["-"]},
          {next: ["-"], predicted: ["2019-09-02 - 2019-09-03"]},
          {next: ["-"], predicted: ["-"]}
        ],
        true => [
          {next: ["-"], predicted: ["-"]},
          {next: ["2019-09-02 - 2019-09-03"], predicted: ["-"]},
          {next: ["-"], predicted: ["-"]}
        ]
      },
    ]

    configs.each_slice(4) do |issue_dates, r_params, check_date, results|
      @issue1.update!(issue_dates)
      rs = r_params.map { |params| create_recurrence(**params) }

      travel_to(check_date)
      results.each do |close, dates|
        close_issue(@issue1) if !@issue1.closed? && close
        reopen_issue(@issue1) if @issue1.closed? && !close

        get issue_path(@issue1)
        assert_response :ok
        rs.each_with_index do |r, i|
          r_next = dates[i][:next].join(", ")
          assert_select "tr#recurrence-#{r.id} p#next", "Next: #{r_next}"
          r_predicted = dates[i][:predicted].join(", ")
          assert_select "tr#recurrence-#{r.id} p#predicted", "Predicted: #{r_predicted}"
        end
      end

      rs.each { |r| destroy_recurrence(r) }
    end
  end

  def test_show_issue_shows_description_based_on_reference_date_without_delay
    @issue1.update!(start_date: Date.new(2019,8,15), due_date: Date.new(2019,8,20))

    anchor_modes = [
      {anchor_mode: :first_issue_fixed},
      {anchor_mode: :last_issue_fixed},
      {anchor_mode: :last_issue_fixed_after_close},
      {anchor_mode: :date_fixed_after_close, anchor_date: Date.new(2019,8,15)},
    ]

    anchor_modes.each do |r_params|
      r_params.update(mode: :monthly_day_from_first, multiplier: 1,
                      delay_mode: :days, delay_multiplier: 4, anchor_to_start: true)
      r = create_recurrence(**r_params)

      get issue_path(@issue1)
      assert_response :ok
      assert_select "tr#recurrence-#{r.id} td:nth-child(1)", /on 15th day/

      destroy_recurrence(r)
    end
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
    # TODO: add creation_mode 'copy' through process_recurrences
    # like: test_renew_anchor_mode_last_issue_flexible_issue_dates_set_and_unset
    @issue1.update!(start_date: Date.new(2019,7,8), due_date: Date.new(2019,7,13))

    travel_to(Date.new(2019,7,1))
    create_recurrence(anchor_mode: :date_fixed_after_close,
                      anchor_to_start: true,
                      mode: :weekly,
                      multiplier: 2,
                      creation_mode: :reopen,
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

  def process_issue_tree(tree, r_issue, **r_params)
    # Sort issues in child-before-parent order
    order = []
    tree_copy = tree.dup
    while !tree_copy.empty?
      childless = tree_copy.select { |k,v| tree_copy.delete(k) || true if v == nil }.keys
      childless = [tree_copy.shift[0]] if childless.empty?
      tree_copy.each { |k,v| tree_copy[k] = nil if childless.include?(v) }
      order += childless
    end
    assert_includes order, r_issue

    IssueRecurrence::creation_modes.each_key do |creation_mode|
      tree.each do |p, c|
        p.update!(start_date: Date.current, due_date: Date.current+9.days)
        p.children.each { |i| set_parent_issue(nil, i) if c != i }
        set_parent_issue(p, c) if c.present? && c.parent != p
        set_parent_issue(nil, p) unless tree.has_value?(p) || p.parent.blank?
      end

      # Issue can be open and have not nil closed_on time if it has been
      # closed+reopened in the past.
      # Issue status should be checked by closed?, not closed_on.
      assert_not order.map(&:closed?).any?

      params = {
        anchor_mode: :last_issue_flexible,
        creation_mode: creation_mode,
        mode: :weekly,
        multiplier: 2,
        include_subtasks: true
      }.update(r_params)

      travel_to(Date.current+2.weeks)
      r = create_recurrence(r_issue, **params)

      subtree_count = order.index(r_issue) + 1
      r_count = params[:include_subtasks] ? subtree_count : 1

      # Child issue has to be closed first
      order[0...subtree_count].each { |i| close_issue(i); assert i.reload.closed? }
      order[subtree_count..r_count].map(&:reload)
      yield(:pre_renew, order)
      issues = if r.reopen?
                 closed = order.select { |i| i.closed? }
                 renew_all(0)
                 closed.reject { |i| i.reload.closed? }
               else
                 Array(renew_all(r_count)).reverse
               end
      assert_equal r_count, issues.length
      issues.each { |i| assert_not i.closed? }
      yield(:post_renew, issues)

      destroy_recurrence(r)
      order.reverse.each { |i| reopen_issue(i) if i.closed?; }.map(&:reload)
    end
  end

  def test_renew_parent_of_new_recurrence_and_its_children_should_be_set_properly
    # Single issue
    tree = {@issue3 => nil}
    process_issue_tree(tree, @issue3) do |stage, issues|
      issue = issues.first
      assert_nil issue.parent
      assert_equal [], issue.children
    end

    # Issue with child
    tree = {@issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2) do |stage, issues|
      child, parent = issues
      assert_nil parent.parent
      assert_equal [child], parent.children
      assert_equal [], child.children
    end

    # Issue with child, recurring without subtasks
    Setting.parent_issue_dates = 'independent'
    tree = {@issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2, include_subtasks: false) do |stage, issues|
      case stage
      when :pre_renew
        child, parent = issues
        assert_nil parent.parent
        assert_equal [child], parent.children
        assert_equal [], child.children
      when :post_renew
        issue = issues.first
        assert_nil issue.parent
        if @issue2.reload.recurrences.first.reopen?
          assert_equal [@issue3.reload], issue.children
          assert_equal [], @issue3.children
        else
          assert_equal [], issue.children
        end
      end
    end
    Setting.parent_issue_dates = 'derived'

    # Issue with child and parent
    tree = {@issue1 => @issue2, @issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2) do |stage, issues|
      case stage
      when :pre_renew
        child, parent, grandparent = issues
        assert_nil grandparent.parent
        assert_equal [parent], grandparent.children
        assert_equal [child], parent.children
        assert_equal [], child.children
      when :post_renew
        child, parent, grandparent = issues + [@issue1.reload]
        assert_nil grandparent.parent
        if @issue2.reload.recurrences.first.reopen?
          assert_equal [parent], grandparent.children
        else
          assert_equal [@issue2.reload, parent], grandparent.children
        end
        assert_equal [child], parent.children
        assert_equal [], child.children
      end
    end
  end

  def test_renew_priority_of_new_recurrence_and_its_children_should_be_set_properly
    default = IssuePriority.default
    non_default = IssuePriority.where(is_default: false).first
    assert_not_nil default
    assert_not_nil non_default
    [@issue1, @issue2, @issue3].each { |i| set_priority(i, non_default) }

    # Single issue
    tree = {@issue3 => nil}
    process_issue_tree(tree, @issue3) do |stage, issues|
      issues.each { |i| assert_equal non_default, i.priority }
    end

    # Issue with child
    tree = {@issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2) do |stage, issues|
      case stage
      when :pre_renew
        child, parent = issues
        # When parent_issue_priority == 'derived', parent is assigned default priority
        # when all children are closed
        assert_equal default, parent.priority
        assert_equal non_default, child.priority
      when :post_renew
        issues.each { |i| assert_equal non_default, i.priority }
      end
    end

    # Issue with child, recurring without subtasks
    Setting.parent_issue_dates = 'independent'
    tree = {@issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2, include_subtasks: false) do |stage, issues|
      case stage
      when :pre_renew
        child, parent = issues
        assert_equal default, parent.priority
        assert_equal non_default, child.priority
      when :post_renew
        assert_equal default, issues.first.priority
        assert_equal non_default, @issue3.reload.priority
      end
    end
    Setting.parent_issue_dates = 'derived'

    # Issue with child and parent
    tree = {@issue1 => @issue2, @issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2) do |stage, issues|
      case stage
      when :pre_renew
        child, parent, grandparent = issues
        assert_equal default, grandparent.priority
        assert_equal default, parent.priority
        assert_equal non_default, child.priority
      when :post_renew
        issues << @issue1.reload
        issues.each { |i| assert_equal non_default, i.priority }
      end
    end

    # Issue with child and parent, priority independent
    Setting.parent_issue_priority = 'independent'
    tree = {@issue1 => @issue2, @issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2) do |stage, issues|
      issues.each { |i| assert_equal non_default, i.priority }
    end
    Setting.parent_issue_priority = 'derived'
  end

  def test_renew_custom_fields_of_new_recurrence_and_its_children_should_be_set_properly
    field = custom_fields(:custom_field_01)
    [@issue1, @issue2, @issue3].each { |i| set_custom_field(i, field, i.subject.reverse) }

    # Single issue
    tree = {@issue3 => nil}
    process_issue_tree(tree, @issue3) do |stage, issues|
      issues.each { |i| assert_equal i.subject.reverse, i.custom_field_value(field) }
    end

    # Issue with child
    tree = {@issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2) do |stage, issues|
      issues.each { |i| assert_equal i.subject.reverse, i.custom_field_value(field) }
    end

    # Issue with child, recurring without subtasks
    Setting.parent_issue_dates = 'independent'
    tree = {@issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2, include_subtasks: false) do |stage, issues|
      issues << @issue3.reload if stage == :post_renew
      issues.each { |i| assert_equal i.subject.reverse, i.custom_field_value(field) }
    end
    Setting.parent_issue_dates = 'derived'

    # Issue with child and parent
    tree = {@issue1 => @issue2, @issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2) do |stage, issues|
      issues << @issue1.reload if stage == :post_renew
      issues.each { |i| assert_equal i.subject.reverse, i.custom_field_value(field) }
    end
  end

  def test_renew_status_of_new_recurrence_and_its_children_should_be_reset
    exp_status = {}
    [@issue1, @issue2, @issue3].each { |i| exp_status[i] = i.tracker.default_status}

    # Single issue
    tree = {@issue3 => nil}
    process_issue_tree(tree, @issue3) do |stage, issues|
      case stage
      when :pre_renew
        issues.each { |i| assert_not_equal exp_status[i], i.status }
      when :post_renew
        assert_equal exp_status[@issue3], issues.first.status
      end
    end

    # Issue with child
    tree = {@issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2) do |stage, issues|
      case stage
      when :pre_renew
        issues.each { |i| assert_not_equal exp_status[i], i.status }
      when :post_renew
        child, parent = issues
        assert_equal parent, child.parent
        assert_equal exp_status[@issue2], parent.status
        assert_equal exp_status[@issue3], child.status
      end
    end

    # Issue with child, recurring without subtasks
    Setting.parent_issue_dates = 'independent'
    tree = {@issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2, include_subtasks: false) do |stage, issues|
      case stage
      when :pre_renew
        issues.each { |i| assert_not_equal exp_status[i], i.status }
      when :post_renew
        assert_equal exp_status[@issue2], issues.first.status
        assert_not_equal exp_status[@issue3], @issue3.reload.status
      end
    end
    Setting.parent_issue_dates = 'derived'

    # Issue with child and parent
    status1 = (IssueStatus.where(is_closed: false) - [exp_status[@issue1]]).first
    @issue1.update!(status: status1)
    tree = {@issue1 => @issue2, @issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2) do |stage, issues|
      case stage
      when :pre_renew
        issues.each { |i| assert_not_equal exp_status[i], i.status }
      when :post_renew
        child, parent = issues
        assert_equal parent, child.parent
        assert_equal status1, @issue1.reload.status
        assert_equal exp_status[@issue2], parent.status
        assert_equal exp_status[@issue3], child.status
      end
    end
  end

  def test_renew_done_ratio_of_new_recurrence_and_its_children_should_be_reset
    assert Issue.use_field_for_done_ratio?

    # Single issue
    tree = {@issue3 => nil}
    [@issue3].each { |i| set_done_ratio(i, 60) }
    process_issue_tree(tree, @issue3) do |stage, issues|
      case stage
      when :pre_renew
        issues.each { |i| assert_not_equal 0, i.done_ratio; assert_not_nil i.done_ratio }
      when :post_renew
        issues.each { |i| assert_equal 0, i.done_ratio }
      end
    end

    # Issue with child
    tree = {@issue2 => @issue3, @issue3 => nil}
    [@issue3, @issue2].each { |i| set_done_ratio(i, 60) }
    process_issue_tree(tree, @issue2) do |stage, issues|
      case stage
      when :pre_renew
        issues.each { |i| assert_not_equal 0, i.done_ratio; assert_not_nil i.done_ratio }
      when :post_renew
        issues.each { |i| assert_equal 0, i.done_ratio }
      end
    end

    # Issue with child, recurring without subtasks
    Setting.parent_issue_dates = 'independent'
    tree = {@issue2 => @issue3, @issue3 => nil}
    [@issue3, @issue2].each { |i| set_done_ratio(i, 60) }
    process_issue_tree(tree, @issue2, include_subtasks: false) do |stage, issues|
      case stage
      when :pre_renew
        issues.each { |i| assert_not_equal 0, i.done_ratio; assert_not_nil i.done_ratio }
      when :post_renew
        assert_equal 0, issues.first.done_ratio
        assert_equal 60, @issue3.reload.done_ratio
      end
    end
    Setting.parent_issue_dates = 'derived'

    # Issue with child and parent
    tree = {@issue1 => @issue2, @issue2 => @issue3, @issue3 => nil}
    [@issue3, @issue2, @issue1].each { |i| set_done_ratio(i, 60) }
    process_issue_tree(tree, @issue2) do |stage, issues|
      case stage
      when :pre_renew
        issues.each { |i| assert_not_equal 0, i.done_ratio; assert_not_nil i.done_ratio }
      when :post_renew
        issues.each { |i| assert_equal 0, i.done_ratio }
        if @issue2.reload.recurrences.first.reopen?
          assert_equal 0, @issue1.reload.done_ratio
        else
          # @issue1 has 2 children now: 1 closed and 1 open
          assert_equal 50, @issue1.reload.done_ratio
        end
      end
    end

    # Issue with child and parent, done ratio independent
    Setting.parent_issue_done_ratio = 'independent'
    tree = {@issue1 => @issue2, @issue2 => @issue3, @issue3 => nil}
    [@issue1, @issue2, @issue3].each { |i| set_done_ratio(i, 60) }
    process_issue_tree(tree, @issue2) do |stage, issues|
      case stage
      when :pre_renew
        issues.each { |i| assert_not_equal 0, i.done_ratio; assert_not_nil i.done_ratio }
      when :post_renew
        issues.each { |i| assert_equal 0, i.done_ratio }
        assert_equal 60, @issue1.reload.done_ratio
      end
    end
    Setting.parent_issue_done_ratio = 'derived'
  end

  def test_renew_time_entries_of_new_recurrence_and_its_children_should_be_reset
    [@issue1, @issue2, @issue3].each_with_index do |i, index|
      set_time_entry(i, (index + 1)*1.5)
    end

    # Single issue
    tree = {@issue3 => nil}
    process_issue_tree(tree, @issue3) do |stage, issues|
      # Timelog entries are left intact when reopening
      if stage == :pre_renew || @issue3.recurrences.first.reopen?
        issues.each { |i| assert_operator 0.0, :<, i.spent_hours }
      else
        issues.each { |i| assert_equal 0.0, i.spent_hours }
      end
    end

    # Issue with child
    tree = {@issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2) do |stage, issues|
      if stage == :pre_renew || @issue2.recurrences.first.reopen?
        issues.each { |i| assert_operator 0.0, :<, i.spent_hours }
      else
        issues.each { |i| assert_equal 0.0, i.spent_hours }
      end
    end

    # Issue with child, recurring without subtasks
    Setting.parent_issue_dates = 'independent'
    tree = {@issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2, include_subtasks: false) do |stage, issues|
      if stage == :pre_renew || @issue2.recurrences.first.reopen?
        issues.each { |i| assert_operator 0.0, :<, i.spent_hours }
      else
        assert_equal 0.0, issues.first.spent_hours
      end
      assert_operator 0.0, :<, @issue3.reload.spent_hours
    end
    Setting.parent_issue_dates = 'derived'

    # Issue with child and parent
    tree = {@issue1 => @issue2, @issue2 => @issue3, @issue3 => nil}
    process_issue_tree(tree, @issue2) do |stage, issues|
      if stage == :pre_renew || @issue2.recurrences.first.reopen?
        issues.each { |i| assert_operator 0.0, :<, i.spent_hours }
      else
        issues.each { |i| assert_equal 0.0, i.spent_hours }
      end
      assert_operator 0.0, :<, @issue1.reload.spent_hours
    end
  end

  def test_renew_creation_mode_reopen_if_issue_not_closed_should_not_recur
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
      r = create_recurrence(**r_params.update(creation_mode: :reopen))
      travel_to(Date.new(2018,11,12))

      assert_equal 0, r.count
      assert !@issue1.closed?
      assert_nil @issue1.closed_on
      renew_all(0)
      assert 0, r.reload.count
      assert !@issue1.reload.closed?

      # Issue.closed_on set to non-nil value while issue status is not closed should
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
            assert_equal [dates[:start]], [r.start_date]
            assert_equal [dates[:due]], [r.due_date]
          end
        end
      end
    end
  end

  def process_recurrences(configs, creation_modes)
    creation_modes.each do |creation_mode|
      configs.each_slice(3) do |issue_dates, r_params, renewals|
        reopen_issue(@issue1) if @issue1.closed?
        @issue1.update!(issue_dates)

        r_params.update(creation_mode: creation_mode)
        travel_to(r_params[:date_limit] - 1.day) if r_params[:date_limit]
        r = create_recurrence(**r_params)

        renewals.each_slice(3) do |travel_close, travel_renew, r_dates|
          r.reload
          if travel_close
            travel_to(travel_close)
            close_issue(r.last_issue || @issue1)
          end
          travel_to(travel_renew)
          irs = if r.reopen?
                  old_attrs = @issue1.reload.attributes
                  renew_all(0)
                  old_attrs != @issue1.reload.attributes ? [@issue1] : []
                else
                  Array(renew_all(r_dates.length))
                end
          assert_equal r_dates.length, irs.length
          irs.each_with_index do |ir, i|
            assert_equal [r_dates[i][:start]], [ir.start_date]
            assert_equal [r_dates[i][:due]], [ir.due_date]
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
          [{start: Date.new(2018,10,15), due: Date.new(2018,11,3)}],
        Date.new(2018,11,15), Date.new(2018,11,16),
          [{start: Date.new(2018,12,15), due: Date.new(2019,1,3)}],
      ],

      # last_issue_flexible, only one date set
      {start_date: Date.new(2018,10,10), due_date: nil},
      {anchor_mode: :last_issue_flexible, mode: :monthly_dow_from_first,
       anchor_to_start: true},
      [
        nil, Date.new(2018,10,12), [],
        Date.new(2018,10,15), Date.new(2018,10,15),
          [{start: Date.new(2018,11,19), due: nil}],
        nil, Date.new(2018,11,25), [],
        Date.new(2018,11,30), Date.new(2018,11,30),
          [{start: Date.new(2018,12,28), due: nil}]
      ],
      {start_date: nil, due_date: Date.new(2018,10,15)},
      {anchor_mode: :last_issue_flexible, mode: :monthly_dow_from_first,
       anchor_to_start: false},
      [
        nil, Date.new(2018,10,19), [],
        Date.new(2018,10,26), Date.new(2018,10,26),
          [{start: nil, due: Date.new(2018,11,23)}],
        nil, Date.new(2018,12,6), [],
        Date.new(2018,12,8), Date.new(2018,12,8),
          [{start: nil, due: Date.new(2019,1,12)}]
      ],

      # last_issue_flexible, both dates unset
      {start_date: nil, due_date: nil},
      {anchor_mode: :last_issue_flexible, mode: :weekly, anchor_to_start: true},
      [
        nil, Date.new(2018,10,12), [],
        Date.new(2018,10,15), Date.new(2018,10,15),
          [{start: Date.new(2018,10,22), due: nil}],
      ],
      {start_date: nil, due_date: nil},
      {anchor_mode: :last_issue_flexible, mode: :weekly, anchor_to_start: false},
      [
        nil, Date.new(2018,10,12), [],
        Date.new(2018,10,15), Date.new(2018,10,15),
          [{start: nil, due: Date.new(2018,10,22)}],
        nil, Date.new(2018,11,25), [],
        Date.new(2018,11,30), Date.new(2018,11,30),
          [{start: nil, due: Date.new(2018,12,7)}]
      ]
    ]

    process_recurrences(configs, [:copy_first, :reopen])
  end

  def test_renew_anchor_mode_last_issue_flexible_on_delay_with_issue_dates_set_and_unset
    configs = [
      # last_issue_flexible_on_delay, both dates set
      {start_date: Date.new(2018,9,13), due_date: Date.new(2018,10,2)},
      {anchor_mode: :last_issue_flexible_on_delay, mode: :monthly_day_from_first,
       anchor_to_start: true},
      [
        Date.new(2018,9,10), Date.new(2018,9,12),
          [{start: Date.new(2018,10,13), due: Date.new(2018,11,1)}],
        Date.new(2018,10,15), Date.new(2018,10,24),
          [{start: Date.new(2018,11,13), due: Date.new(2018,12,2)}],
        Date.new(2018,12,15), Date.new(2018,12,15),
          [{start: Date.new(2019,1,15), due: Date.new(2019,2,3)}],
      ],

      # last_issue_flexible_on_delay, only one date set
      {start_date: Date.new(2018,10,10), due_date: nil},
      {anchor_mode: :last_issue_flexible_on_delay, mode: :monthly_dow_from_first,
       anchor_to_start: true},
      [
        nil, Date.new(2018,10,9), [],
        Date.new(2018,10,9), Date.new(2018,10,9),
          [{start: Date.new(2018,11,14), due: nil}],
        nil, Date.new(2018,11,13), [],
        Date.new(2018,11,14), Date.new(2018,11,20),
          [{start: Date.new(2018,12,12), due: nil}],
        nil, Date.new(2018,12,25), [],
        Date.new(2018,12,30), Date.new(2018,12,30),
          [{start: Date.new(2019,1,27), due: nil}]
      ],
      {start_date: nil, due_date: Date.new(2018,10,15)},
      {anchor_mode: :last_issue_flexible_on_delay, mode: :monthly_dow_from_first,
       anchor_to_start: false},
      [
        nil, Date.new(2018,10,10), [],
        Date.new(2018,10,13), Date.new(2018,10,13),
          [{start: nil, due: Date.new(2018,11,19)}],
        nil, Date.new(2018,12,20), [],
        Date.new(2018,12,20), Date.new(2018,12,28),
          [{start: nil, due: Date.new(2019,1,17)}]
      ],

      # last_issue_flexible_on_delay, both dates unset - same as last_issue_flexible
      {start_date: nil, due_date: nil},
      {anchor_mode: :last_issue_flexible_on_delay, mode: :weekly, anchor_to_start: true},
      [
        nil, Date.new(2018,10,12), [],
        Date.new(2018,10,15), Date.new(2018,10,15),
          [{start: Date.new(2018,10,22), due: nil}],
      ],
      {start_date: nil, due_date: nil},
      {anchor_mode: :last_issue_flexible_on_delay, mode: :weekly, anchor_to_start: false},
      [
        nil, Date.new(2018,10,12), [],
        Date.new(2018,10,15), Date.new(2018,10,15),
          [{start: nil, due: Date.new(2018,10,22)}],
        nil, Date.new(2018,11,25), [],
        Date.new(2018,11,30), Date.new(2018,11,30),
          [{start: nil, due: Date.new(2018,12,7)}]
      ]
    ]

    process_recurrences(configs, [:copy_first, :reopen])
  end

  def test_renew_anchor_mode_last_issue_fixed_after_close_with_issue_dates_set_and_unset
    configs = [
      # last_issue_fixed_after_close, both dates set
      {start_date: Date.new(2018,9,13), due_date: Date.new(2018,10,2)},
      {anchor_mode: :last_issue_fixed_after_close, mode: :monthly_day_from_first,
       anchor_to_start: true},
      [
        Date.new(2018,9,15), Date.new(2018,11,4),
          [{start: Date.new(2018,10,13), due: Date.new(2018,11,1)}],
        Date.new(2019,1,15), Date.new(2018,1,15),
          [{start: Date.new(2019,2,13), due: Date.new(2019,3,4)}],
        Date.new(2019,2,12), Date.new(2018,2,12),
          [{start: Date.new(2019,3,13), due: Date.new(2019,4,1)}],
      ],

      # last_issue_fixed_after_close, only one date set
      {start_date: Date.new(2018,10,10), due_date: nil},
      {anchor_mode: :last_issue_fixed_after_close, mode: :monthly_dow_from_first,
       anchor_to_start: true},
      [
        nil, Date.new(2018,10,9), [],
        Date.new(2018,10,9), Date.new(2018,10,9),
          [{start: Date.new(2018,11,14), due: nil}],
        Date.new(2018,12,30), Date.new(2018,12,31),
          [{start: Date.new(2019,1,9), due: nil}],
        nil, Date.new(2019,3,25), [],
        Date.new(2019,3,30), Date.new(2019,3,30),
          [{start: Date.new(2019,4,10), due: nil}]
      ],

      {start_date: nil, due_date: Date.new(2018,10,15)},
      {anchor_mode: :last_issue_fixed_after_close, mode: :monthly_dow_from_first,
       anchor_to_start: false},
      [
        Date.new(2019,2,17), Date.new(2019,2,17),
          [{start: nil, due: Date.new(2019,2,18)}],
        nil, Date.new(2019,2,18), [],
        Date.new(2019,4,15), Date.new(2019,4,15),
          [{start: nil, due: Date.new(2019,5,20)}]
      ]

      # last_issue_fixed_after_close, both dates unset disallowed
    ]

    process_recurrences(configs, [:copy_first, :reopen])
  end

  def test_renew_anchor_mode_date_fixed_after_close_with_issue_dates_set_and_unset
    configs = [
      # date_fixed_after_close, both dates set
      {start_date: Date.new(2018,9,13), due_date: Date.new(2018,10,2)},
      {anchor_mode: :date_fixed_after_close, mode: :monthly_day_from_first,
       anchor_to_start: true, anchor_date: Date.new(2018,9,5)},
      [
        Date.new(2018,12,15), Date.new(2018,12,24),
          [{start: Date.new(2019,1,5), due: Date.new(2019,1,24)}],
        Date.new(2019,1,4), Date.new(2018,1,4),
          [{start: Date.new(2019,2,5), due: Date.new(2019,2,24)}],
      ],

      # date_fixed_after_close, only one date set
      {start_date: Date.new(2018,10,10), due_date: nil},
      {anchor_mode: :date_fixed_after_close, mode: :monthly_dow_from_first,
       anchor_to_start: true, anchor_date: Date.new(2018,11,5)},
      [
        nil, Date.new(2018,12,9), [],
        Date.new(2019,1,9), Date.new(2019,1,9),
          [{start: Date.new(2019,2,4), due: nil}],
        Date.new(2019,2,3), Date.new(2019,2,4),
          [{start: Date.new(2019,3,4), due: nil}],
      ],

      {start_date: nil, due_date: Date.new(2018,10,15)},
      {anchor_mode: :date_fixed_after_close, mode: :monthly_dow_to_last,
       anchor_to_start: false, anchor_date: Date.new(2018,12,31)},
      [
        Date.new(2018,12,30), Date.new(2018,12,30),
          [{start: nil, due: Date.new(2018,12,31)}],
        Date.new(2019,2,17), Date.new(2019,2,17),
          [{start: nil, due: Date.new(2019,2,25)}],
        nil, Date.new(2019,2,18), [],
        Date.new(2019,2,25), Date.new(2019,2,25),
          [{start: nil, due: Date.new(2019,3,25)}]
      ],

      # date_fixed_after_close, both dates unset
      {start_date: nil, due_date: nil},
      {anchor_mode: :date_fixed_after_close, mode: :weekly,
       anchor_to_start: true, anchor_date: Date.new(2019,6,7)},
      [
        nil, Date.new(2019,7,17), [],
        Date.new(2019,7,18), Date.new(2019,7,18),
          [{start: Date.new(2019,7,19), due: nil}],
      ],

      {start_date: nil, due_date: nil},
      {anchor_mode: :date_fixed_after_close, mode: :weekly,
       anchor_to_start: false, anchor_date: Date.new(2019,6,7)},
      [
        nil, Date.new(2019,7,17), [],
        Date.new(2019,7,18), Date.new(2019,7,18),
          [{start: nil, due: Date.new(2019,7,19)}],
        Date.new(2019,7,26), Date.new(2019,7,26),
          [{start: nil, due: Date.new(2019,8,2)}]
      ]
    ]

    process_recurrences(configs, [:copy_first, :reopen])
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

      r = create_recurrence(**r_params.update(mode: :monthly_day_from_first))

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

      r = create_recurrence(**r_params)

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

      ir = create_recurrence(**r_params.update(mode: :yearly))

      r = renew_all(1)
      assert_equal r_dates[:start], r.start_date
      assert_equal r_dates[:due], r.due_date
    end
  end

  def test_renew_with_delay
    r_defaults = {
       anchor_to_start: true,
       mode: :monthly_day_from_first,
       delay_mode: :days,
       delay_multiplier: 10
    }

    configs = [
      # delay w/o limit
      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      r_defaults.merge(anchor_mode: :first_issue_fixed),
      [
        nil, Date.new(2019,9,14), [],
        nil, Date.new(2019,9,15),
          [{start: Date.new(2019,10,25), due: Date.new(2019,10,30)}],
        nil, Date.new(2019,10,24), [],
        nil, Date.new(2019,12,24),
        [
          {start: Date.new(2019,11,25), due: Date.new(2019,11,30)},
          {start: Date.new(2019,12,25), due: Date.new(2019,12,30)}
        ],
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      r_defaults.merge(anchor_mode: :last_issue_fixed),
      [
        nil, Date.new(2019,9,14), [],
        nil, Date.new(2019,9,15),
          [{start: Date.new(2019,10,25), due: Date.new(2019,10,30)}],
        nil, Date.new(2019,10,24), [],
        nil, Date.new(2019,12,24),
        [
          {start: Date.new(2019,11,25), due: Date.new(2019,11,30)},
          {start: Date.new(2019,12,25), due: Date.new(2019,12,30)}
        ],
      ],

      # delay with date limit
      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      r_defaults.merge(anchor_mode: :last_issue_fixed, date_limit: Date.new(2019,12,25)),
      [
        nil, Date.new(2019,12,24),
        [
          {start: Date.new(2019,10,25), due: Date.new(2019,10,30)},
          {start: Date.new(2019,11,25), due: Date.new(2019,11,30)},
          {start: Date.new(2019,12,25), due: Date.new(2019,12,30)}
        ],
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      r_defaults.merge(anchor_mode: :last_issue_fixed, date_limit: Date.new(2019,12,24)),
      [
        nil, Date.new(2019,12,24),
        [
          {start: Date.new(2019,10,25), due: Date.new(2019,10,30)},
          {start: Date.new(2019,11,25), due: Date.new(2019,11,30)},
        ],
      ],
    ]

    configs_reopen = [
      # delay w/o limit
      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      r_defaults.merge(anchor_mode: :last_issue_fixed_after_close),
      [
        nil, Date.new(2019,9,14), [],
        Date.new(2019,9,14), Date.new(2019,9,15),
          [{start: Date.new(2019,10,25), due: Date.new(2019,10,30)}],
        nil, Date.new(2019,10,24), [],
        Date.new(2019,10,24), Date.new(2019,12,24),
          [{start: Date.new(2019,11,25), due: Date.new(2019,11,30)}],
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      r_defaults.merge(anchor_mode: :date_fixed_after_close,
                       anchor_date: Date.new(2019,9,15)),
      [
        nil, Date.new(2019,9,14), [],
        Date.new(2019,9,14), Date.new(2019,9,15),
          [{start: Date.new(2019,10,25), due: Date.new(2019,10,30)}],
        nil, Date.new(2019,10,24), [],
        Date.new(2019,10,24), Date.new(2019,12,24),
          [{start: Date.new(2019,11,25), due: Date.new(2019,11,30)}],
      ],

      # delay with date limit
      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      r_defaults.merge(anchor_mode: :last_issue_fixed_after_close,
                       date_limit: Date.new(2019,11,25)),
      [
        Date.new(2019,9,14), Date.new(2019,9,15),
          [{start: Date.new(2019,10,25), due: Date.new(2019,10,30)}],
        Date.new(2019,10,24), Date.new(2019,12,24),
          [{start: Date.new(2019,11,25), due: Date.new(2019,11,30)}],
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      r_defaults.merge(anchor_mode: :last_issue_fixed_after_close,
                       date_limit: Date.new(2019,11,24)),
      [
        Date.new(2019,9,14), Date.new(2019,9,15),
          [{start: Date.new(2019,10,25), due: Date.new(2019,10,30)}],
        Date.new(2019,10,24), Date.new(2019,12,24),
          [],
      ],
    ]

    process_recurrences(configs, [:copy_first])
    process_recurrences(configs_reopen, [:reopen])
  end

  def test_renew_with_delay_should_add_delay_after_mode
    configs = [
      {anchor_mode: :first_issue_fixed},
      [
        {start: Date.new(2019,3,2), due: Date.new(2019,3,4)},
        {start: Date.new(2019,3,31), due: Date.new(2019,4,2)}
      ],

      {anchor_mode: :last_issue_fixed},
      [
        {start: Date.new(2019,3,2), due: Date.new(2019,3,4)},
        {start: Date.new(2019,4,2), due: Date.new(2019,4,4)}
      ],

      {anchor_mode: :last_issue_fixed_after_close},
      [{start: Date.new(2019,3,2), due: Date.new(2019,3,4)}],

      {anchor_mode: :date_fixed_after_close, anchor_date: Date.new(2019,1,29),
       creation_mode: :reopen},
      [{start: Date.new(2019,3,2), due: Date.new(2019,3,4)}],
    ]

    configs.each_slice(2) do |r_params, renews|
      reopen_issue(@issue1) if @issue1.closed?
      @issue1.update!(start_date: Date.new(2019,1,29), due_date: Date.new(2019,1,31))

      r_params.update(anchor_to_start: true,
                      mode: :monthly_day_from_first,
                      delay_mode: :days,
                      delay_multiplier: 2)
      travel_to(Date.new(2019,2,1))
      r = create_recurrence(**r_params)

      close_issue(@issue1) if r_params[:anchor_mode].to_s.include?("_after_close")
      travel_to(Date.new(2019,3,2))
      r1s = if r.reopen?
              renew_all(0)
              [@issue1.reload]
            else
              Array(renew_all(renews.length))
            end
      r1s.each_with_index do |r, i|
        assert_equal renews[i][:start], r.start_date
        assert_equal renews[i][:due], r.due_date
      end

      destroy_recurrence(r)
    end
  end

  def test_renew_with_count_limit
    configs = [
      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :first_issue_fixed, count_limit: 4},
      [
        nil, Date.new(2019,9,28),
        [
          {start: Date.new(2019,9,22), due: Date.new(2019,9,27)},
          {start: Date.new(2019,9,29), due: Date.new(2019,10,4)}
        ],
        nil, Date.new(2019,10,28),
        [
          {start: Date.new(2019,10,6), due: Date.new(2019,10,11)},
          {start: Date.new(2019,10,13), due: Date.new(2019,10,18)},
        ],
        nil, Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :first_issue_fixed, count_limit: 0},
      [
        nil, Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_fixed, count_limit: 4},
      [
        nil, Date.new(2019,9,28),
        [
          {start: Date.new(2019,9,22), due: Date.new(2019,9,27)},
          {start: Date.new(2019,9,29), due: Date.new(2019,10,4)}
        ],
        nil, Date.new(2019,10,28),
        [
          {start: Date.new(2019,10,6), due: Date.new(2019,10,11)},
          {start: Date.new(2019,10,13), due: Date.new(2019,10,18)},
        ],
        nil, Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_fixed, count_limit: 0},
      [
        nil, Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_flexible, count_limit: 2},
      [
        Date.new(2019,9,28), Date.new(2019,9,28),
        [
          {start: Date.new(2019,9,30), due: Date.new(2019,10,5)}
        ],
        Date.new(2019,10,10), Date.new(2019,10,10),
        [
          {start: Date.new(2019,10,12), due: Date.new(2019,10,17)}
        ],
        Date.new(2019,11,28), Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_flexible, count_limit: 0},
      [
        Date.new(2019,11,28), Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_flexible_on_delay, count_limit: 2},
      [
        Date.new(2019,9,28), Date.new(2019,9,28),
        [
          {start: Date.new(2019,9,30), due: Date.new(2019,10,5)}
        ],
        Date.new(2019,10,10), Date.new(2019,10,10),
        [
          {start: Date.new(2019,10,12), due: Date.new(2019,10,17)}
        ],
        Date.new(2019,11,28), Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_flexible_on_delay, count_limit: 0},
      [
        Date.new(2019,11,28), Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_fixed_after_close, count_limit: 2},
      [
        Date.new(2019,9,28), Date.new(2019,9,28),
        [
          {start: Date.new(2019,9,29), due: Date.new(2019,10,4)}
        ],
        Date.new(2019,10,5), Date.new(2019,10,5),
        [
          {start: Date.new(2019,10,6), due: Date.new(2019,10,11)}
        ],
        Date.new(2019,11,28), Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_fixed_after_close, count_limit: 0},
      [
        Date.new(2019,11,28), Date.new(2019,11,28), []
      ],
    ]

    configs_reopen = [
      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :date_fixed_after_close, anchor_date: Date.new(2019,9,15),
       count_limit: 2},
      [
        Date.new(2019,9,28), Date.new(2019,9,28),
        [
          {start: Date.new(2019,10,1), due: Date.new(2019,10,6)}
        ],
        Date.new(2019,10,5), Date.new(2019,10,5),
        [
          {start: Date.new(2019,10,8), due: Date.new(2019,10,13)}
        ],
        Date.new(2019,11,28), Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :date_fixed_after_close, anchor_date: Date.new(2019,9,15),
       count_limit: 0},
      [
        Date.new(2019,11,28), Date.new(2019,11,28), []
      ],
    ]

    process_recurrences(configs, [:copy_first])
    process_recurrences(configs_reopen, [:reopen])
  end

  def test_renew_with_date_limit
    configs = [
      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :first_issue_fixed, date_limit: Date.new(2019,10,19)},
      [
        nil, Date.new(2019,9,28),
        [
          {start: Date.new(2019,9,22), due: Date.new(2019,9,27)},
          {start: Date.new(2019,9,29), due: Date.new(2019,10,4)}
        ],
        nil, Date.new(2019,10,28),
        [
          {start: Date.new(2019,10,6), due: Date.new(2019,10,11)},
          {start: Date.new(2019,10,13), due: Date.new(2019,10,18)},
        ],
        nil, Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :first_issue_fixed, date_limit: Date.new(2019,9,21)},
      [
        nil, Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_fixed, date_limit: Date.new(2019,10,19)},
      [
        nil, Date.new(2019,9,28),
        [
          {start: Date.new(2019,9,22), due: Date.new(2019,9,27)},
          {start: Date.new(2019,9,29), due: Date.new(2019,10,4)}
        ],
        nil, Date.new(2019,10,28),
        [
          {start: Date.new(2019,10,6), due: Date.new(2019,10,11)},
          {start: Date.new(2019,10,13), due: Date.new(2019,10,18)},
        ],
        nil, Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_fixed, date_limit: Date.new(2019,9,21)},
      [
        nil, Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_flexible, date_limit: Date.new(2019,11,29)},
      [
        Date.new(2019,9,28), Date.new(2019,9,28),
        [
          {start: Date.new(2019,9,30), due: Date.new(2019,10,5)}
        ],
        Date.new(2019,10,10), Date.new(2019,10,10),
        [
          {start: Date.new(2019,10,12), due: Date.new(2019,10,17)}
        ],
        Date.new(2019,11,28), Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_flexible, date_limit: Date.new(2019,11,30)},
      [
        Date.new(2019,11,28), Date.new(2019,11,28),
        [
          {start: Date.new(2019,11,30), due: Date.new(2019,12,5)}
        ],
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_flexible_on_delay, date_limit: Date.new(2019,11,29)},
      [
        Date.new(2019,9,28), Date.new(2019,9,28),
        [
          {start: Date.new(2019,9,30), due: Date.new(2019,10,5)}
        ],
        Date.new(2019,10,10), Date.new(2019,10,10),
        [
          {start: Date.new(2019,10,12), due: Date.new(2019,10,17)}
        ],
        Date.new(2019,11,28), Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_flexible_on_delay, date_limit: Date.new(2019,11,30)},
      [
        Date.new(2019,11,28), Date.new(2019,11,28),
        [
          {start: Date.new(2019,11,30), due: Date.new(2019,12,5)}
        ],
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_fixed_after_close, date_limit: Date.new(2019,11,30)},
      [
        Date.new(2019,9,28), Date.new(2019,9,28),
        [
          {start: Date.new(2019,9,29), due: Date.new(2019,10,4)}
        ],
        Date.new(2019,10,5), Date.new(2019,10,5),
        [
          {start: Date.new(2019,10,6), due: Date.new(2019,10,11)}
        ],
        Date.new(2019,11,28), Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :last_issue_fixed_after_close, date_limit: Date.new(2019,12,1)},
      [
        Date.new(2019,11,28), Date.new(2019,11,28),
        [
          {start: Date.new(2019,12,1), due: Date.new(2019,12,6)}
        ]
      ],
    ]

    configs_reopen = [
      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :date_fixed_after_close, anchor_date: Date.new(2019,9,15),
       date_limit: Date.new(2019,12,2)},
      [
        Date.new(2019,9,28), Date.new(2019,9,28),
        [
          {start: Date.new(2019,10,1), due: Date.new(2019,10,6)}
        ],
        Date.new(2019,10,5), Date.new(2019,10,5),
        [
          {start: Date.new(2019,10,8), due: Date.new(2019,10,13)}
        ],
        Date.new(2019,11,28), Date.new(2019,11,28), []
      ],

      {start_date: Date.new(2019,9,15), due_date: Date.new(2019,9,20)},
      {anchor_mode: :date_fixed_after_close, anchor_date: Date.new(2019,9,15),
       date_limit: Date.new(2019,12,3)},
      [
        Date.new(2019,11,28), Date.new(2019,11,28),
        [
          {start: Date.new(2019,12,3), due: Date.new(2019,12,8)}
        ]
      ],
    ]

    process_recurrences(configs, [:copy_first])
    process_recurrences(configs_reopen, [:reopen])
  end

  def test_renew_should_create_issues_independently_from_recurence_creation_order
    # Testing following rules:
    # - multiple reopens should recur at the time of the earliest one,
    # - reopen and non-reopen should recur based on the same reference dates
    # (i.e. when reopen is created/applied first, its resulting dates should
    # not be reference dates for non-reopen)
    recurrences = [
      {anchor_mode: :first_issue_fixed, mode: :weekly, multiplier: 3,
       delay_mode: :days, delay_multiplier: 3},
      {anchor_mode: :last_issue_fixed, mode: :daily, multiplier: 18},
      {anchor_mode: :last_issue_flexible, mode: :daily, multiplier: 10,
       creation_mode: :reopen},
      {anchor_mode: :date_fixed_after_close, mode: :weekly, multiplier: 2,
       creation_mode: :reopen, anchor_date: Date.new(2019,7,29)},
    ]

    recurrences.permutation.each_with_index do |r_perm|
      reopen_issue(@issue1) if @issue1.closed?
      @issue1.update!(start_date: Date.new(2019,7,31), due_date: Date.new(2019,8,4))

      travel_to(Date.new(2019,7,25))
      rs = r_perm.map do |r_params|
        r_params.update(anchor_to_start: true)
        create_recurrence(**r_params)
      end

      travel_to(Date.new(2019,8,20))
      close_issue(@issue1)

      travel_to(Date.new(2019,9,1))
      irs = renew_all(4)
      @issue1.reload
      # 1: [2019,8,24, 2019,9,14], 2: [2019,8,18, 2019,9,5], 3: [], 4: [2019,8,28]
      assert_equal Date.new(2019,8,26), @issue1.start_date
      assert_equal Date.new(2019,8,30), @issue1.due_date
      dates = [
        {start: Date.new(2019,8,18), due: Date.new(2019,8,22)},
        {start: Date.new(2019,8,24), due: Date.new(2019,8,28)},
        {start: Date.new(2019,9,5), due: Date.new(2019,9,9)},
        {start: Date.new(2019,9,14), due: Date.new(2019,9,18)},
      ]
      irs.sort! { |a, b| a.start_date <=> b.start_date }
      irs.each_with_index do |r, i|
        assert_equal dates[i][:start], r.start_date
        assert_equal dates[i][:due], r.due_date
      end

      travel_to(Date.new(2019,8,27))
      close_issue(@issue1)
      renew_all(0)
      @issue1.reload
      # 1: [], 2: [], 3: [2019,9,6], 4: []
      assert_equal Date.new(2019,9,6), @issue1.start_date
      assert_equal Date.new(2019,9,10), @issue1.due_date

      rs.each { |r| destroy_recurrence(r) }
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

  def test_copying_issue_resets_recurrence_of
    @issue1.update!(start_date: 10.days.ago, due_date: 5.days.ago)
    ir = create_recurrence
    travel_to(@issue1.start_date)
    r1 = renew_all(1)
    assert_equal @issue1, r1.recurrence_of

    r1_copy = copy_issue(r1, r1.project)
    assert_nil r1_copy.recurrence_of
  end

  def test_copying_issue_with_changes_that_invalidate_recurrence_should_fail
    @issue1.update!(start_date: 10.days.ago, due_date: 5.days.ago)
    ir = create_recurrence(anchor_to_start: false)

    issue1_copy = copy_issue(@issue1, @project1)
    refute_empty issue1_copy.recurrences

    errors = copy_issue_should_fail(@issue1, @project1, due_date: nil)
    assert errors.added?(:recurrences, :invalid)
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

      create_recurrence(**r_params.update(include_subtasks: true))
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

  def test_renew_creation_mode_reopen
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    r = create_recurrence(creation_mode: :reopen, anchor_mode: :last_issue_flexible)
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

  def test_renew_applies_author_login_configuration_setting
    # NOTE: to be removed when system tests are working with all supported Redmine versions.
    # * corresponding system test: test_settings_author_login
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))
    create_recurrence(creation_mode: :copy_first)

    assert_equal users(:bob), @issue1.author

    logout_user
    log_user 'admin', 'foo'

    update_plugin_settings(author_id: 0)
    travel_to(@issue1.start_date)
    r1 = renew_all(1)
    assert_equal users(:bob), r1.author

    update_plugin_settings(author_id: users(:charlie).id)
    travel_to(r1.start_date)
    r2 = renew_all(1)
    assert_equal users(:charlie), r2.author
  end

  def test_renew_logs_warning_for_nonexistent_author_login_exclusively
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))
    create_recurrence(creation_mode: :copy_first)

    assert_equal users(:bob), @issue1.author

    logout_user
    log_user 'admin', 'foo'
    update_plugin_settings(author_id: users(:charlie).id)
    r = {}

    # User exists
    travel_to(@issue1.start_date)
    assert_no_difference 'Journal.count' do
      r[1] = renew_all(1)
    end
    assert_equal users(:charlie), r[1].author

    # User doesn't exist
    destroy_user(users(:charlie))
    travel_to(r[1].start_date)
    assert_difference ['Journal.count', '@issue1.journals.count'], 1 do
      r[2] = renew_all(1)
    end
    assert_equal users(:bob), r[2].author
    msg = "#{I18n.t(:warning_author, id: r[2].id, login: users(:charlie).login)}\r\n"
    assert_equal msg, Journal.last.notes
  end

  def test_renew_applies_keep_assignee_configuration_setting
    # NOTE: to be removed when system tests are working with all supported Redmine versions.
    # * corresponding system test: test_settings_keep_assignee
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))
    create_recurrence(creation_mode: :copy_first)

    assert_equal users(:alice), @issue1.assigned_to
    assert_equal users(:gopher), @issue1.project.default_assigned_to

    logout_user
    log_user 'admin', 'foo'

    update_plugin_settings(keep_assignee: false)
    travel_to(@issue1.start_date)
    r1 = renew_all(1)
    assert_equal users(:gopher), r1.assigned_to

    update_plugin_settings(keep_assignee: true)
    travel_to(r1.start_date)
    r2 = renew_all(1)
    assert_equal users(:alice), r2.assigned_to
  end

  def test_renew_logs_warning_for_unassignable_users_exclusively
    # https://it.michalczyk.pro/issues/26
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))
    create_recurrence(creation_mode: :copy_first)

    assert_equal users(:alice), @issue1.assigned_to
    assert_equal users(:gopher), @issue1.project.default_assigned_to

    logout_user
    log_user 'admin', 'foo'
    update_plugin_settings(keep_assignee: true)
    r = {}

    # Blocked user is not assignable
    set_user_status(users(:alice), Principal::STATUS_LOCKED)
    travel_to(@issue1.start_date)
    assert_difference ['Journal.count', '@issue1.journals.count'], 1 do
      r[1] = renew_all(1)
    end
    assert_equal users(:gopher), r[1].assigned_to
    msg = "#{I18n.t(:warning_keep_assignee, id: r[1].id, login: users(:alice).login)}\r\n"
    assert_equal msg, Journal.last.notes

    # Active user is assignable
    set_user_status(users(:alice), Principal::STATUS_ACTIVE)
    travel_to(r[1].start_date)
    assert_no_difference 'Journal.count' do
      r[2] = renew_all(1)
    end
    assert_equal users(:alice), r[2].assigned_to

    # nil user is assignable, but Redmine assigns default anyway
    set_assigned_to(@issue1, nil)
    travel_to(r[2].start_date)
    assert_no_difference 'Journal.count' do
      r[3] = renew_all(1)
    end
    assert_equal users(:gopher), r[3].assigned_to
  end

  def test_renew_applies_journal_mode_configuration_setting
    # NOTE: to be removed when system tests are working with all supported Redmine versions.
    # * corresponding system test: test_settings_journal_mode
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))
    @issue2.update!(start_date: Date.new(2018,9,15), due_date: Date.new(2018,9,20))

    ir1 = create_recurrence(@issue1, creation_mode: :copy_first, anchor_to_start: true)
    ir2 = create_recurrence(@issue2, creation_mode: :reopen, anchor_to_start: true,
                            anchor_mode: :last_issue_flexible)

    logout_user
    log_user 'admin', 'foo'

    configs = [
      {mode: :never, journalized: []},
      {mode: :always, journalized: [@issue1, @issue2]},
      {mode: :on_reopen, journalized: [@issue2]}
    ]

    configs.each do |config|
      update_plugin_settings(journal_mode: config[:mode])

      assert_equal (ir1.last_issue || @issue1).start_date, @issue2.start_date
      travel_to(@issue2.start_date)
      close_issue(@issue2)
      count = config[:journalized].length
      assert_difference 'Journal.count', count do renew_all(1) end
      [ir1, @issue1, @issue2].map(&:reload)
      assert !@issue2.closed?
      if count > 0
        assert_equal config[:journalized], Journal.last(count).map(&:journalized)
        assert_equal config[:journalized].map(&:author), Journal.last(count).map(&:user)
      end
    end
  end

  def test_copying_issue_applies_copy_recurrences_configuration_setting
    # NOTE: to be removed when system tests are working with all supported Redmine versions.
    # * corresponding system test: test_settings_copy_recurrences
    malleable_attrs = [:id, :created_at, :updated_at, :issue_id, :last_issue_id, :count]
    fixed_attrs = ->(ir) { ir.attributes.with_indifferent_access.except(*malleable_attrs) }


    @issue1.update!(start_date: 10.days.ago, due_date: 5.days.ago)
    ir = create_recurrence(creation_mode: :copy_first)
    logout_user
    log_user 'admin', 'foo'
    update_plugin_settings(copy_recurrences: false)

    # copy_recurrences: false -> copy project
    assert_no_difference 'IssueRecurrence.count' do
      project_copy = copy_project(@project1)
      assert_equal @project1, ir.reload.issue.project
    end

    logout_user
    log_user 'alice', 'foo'

    # copy_recurrences: false -> copy issue
    assert_no_difference 'IssueRecurrence.count' do
      issue_copy = copy_issue(@issue1, @project1)
      assert_equal @issue1, ir.reload.issue
    end

    # copy_recurrences: false -> recur issue
    travel_to(@issue1.start_date)
    assert_no_difference 'IssueRecurrence.count' do
      renew_all(1)
    end

    destroy_recurrence(ir)


    @issue1.update!(start_date: 10.days.ago, due_date: 5.days.ago)
    ir = create_recurrence(creation_mode: :copy_first)
    # Recur once and update :last_issue and :count
    travel_to(@issue1.start_date)
    r1 = renew_all(1)
    ir.reload
    assert_not_nil ir.last_issue
    assert_not_equal 0, ir.count

    logout_user
    log_user 'admin', 'foo'
    update_plugin_settings(copy_recurrences: true)

    # copy_recurrences: true -> copy project
    assert_difference 'IssueRecurrence.count', 1 do
      project_copy = copy_project(@project1)
      ir_copy = IssueRecurrence.last
      assert_equal project_copy, ir_copy.issue.project
      assert_equal fixed_attrs.(ir), fixed_attrs.(ir_copy)
      assert_nil ir_copy.last_issue
      assert_equal 0, ir_copy.count
    end

    logout_user
    log_user 'alice', 'foo'

    # copy_recurrences: true -> copy issue
    assert_difference 'IssueRecurrence.count', 1 do
      issue_copy = copy_issue(@issue1, @project1)
      ir_copy = IssueRecurrence.last
      assert_equal issue_copy, ir_copy.issue
      assert_equal fixed_attrs.(ir), fixed_attrs.(ir_copy)
      assert_nil ir_copy.last_issue
      assert_equal 0, ir_copy.count
    end

    # copy_recurrences: true -> recur issue and its copies created above
    travel_to(r1.start_date)
    assert_no_difference 'IssueRecurrence.count' do
      # Copies are renewed twice and original once (it has already beed renewed
      # once during setup)
      renew_all(5)
    end
  end

  def test_renew_applies_renew_ahead_configuration_settings
    # NOTE: to be removed when system tests are working with all supported Redmine versions.
    # * corresponding system test: test_settings_renew_ahead
    @issue1.update!(start_date: Date.new(2020,7,12), due_date: Date.new(2020,7,17))

    logout_user
    log_user 'admin', 'foo'

    [:first_issue_fixed, :last_issue_fixed].each do |am|
      ir = create_recurrence(creation_mode: :copy_first, mode: :weekly, anchor_mode: am)

      travel_to(@issue1.start_date - 1.week)
      update_plugin_settings(ahead_multiplier: 6, ahead_mode: :days)
      renew_all(0)

      update_plugin_settings(ahead_multiplier: 1, ahead_mode: :weeks)
      r1 = renew_all(1)
      assert_equal Date.new(2020,7,19), r1.start_date
      assert_equal Date.new(2020,7,24), r1.due_date

      update_plugin_settings(ahead_multiplier: 1, ahead_mode: :months)
      rest = renew_all(3)
      assert_equal [Date.new(2020,7,26), Date.new(2020,8,2), Date.new(2020,8,9)],
        rest.map(&:start_date)
      assert_equal [Date.new(2020,7,31), Date.new(2020,8,7), Date.new(2020,8,14)],
        rest.map(&:due_date)

      update_plugin_settings(ahead_multiplier: 0, ahead_mode: :months)
      travel_to(rest.last.start_date - 1.day)
      renew_all(0)

      destroy_recurrence(ir)
    end
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
                      anchor_to_start: true, creation_mode: :reopen,
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

  def test_renew_multiple_creation_mode_reopen_anchor_mode_date_fixed_after_close
    @issue1.update!(start_date: Date.new(2019,7,12), due_date: Date.new(2019,7,13))

    # Recur every 15th and last day of month, but not less often than every 10 days.
    create_recurrence(anchor_mode: :date_fixed_after_close,
                     anchor_to_start: true,
                     anchor_date: Date.new(2019,6,30),
                     mode: :monthly_day_to_last,
                     multiplier: 1,
                     creation_mode: :reopen)
    create_recurrence(anchor_mode: :date_fixed_after_close,
                     anchor_to_start: true,
                     anchor_date: Date.new(2019,6,15),
                     mode: :monthly_day_from_first,
                     multiplier: 1,
                     creation_mode: :reopen)
    create_recurrence(anchor_mode: :last_issue_flexible,
                     anchor_to_start: true,
                     mode: :daily,
                     multiplier: 10,
                     creation_mode: :reopen)

    # close date, recurrence dates
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

  def test_renew_logs_warning_for_anchor_mode_fixed_after_both_dates_removed
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
      @issue1.reload
      assert_equal @issue1, Journal.last.journalized
      errors = ir.errors.generate_message(:anchor_mode, :blank_issue_dates_require_reopen)
      msg = "#{I18n.t(:warning_renew, id: ref_issue.id, errors: errors)}\r\n"
      assert_equal msg, Journal.last.notes

      destroy_recurrence(ir)
    end
  end

  def test_renew_logs_warning_for_anchor_mode_fixed_after_anchor_date_removed
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
      @issue1.reload
      assert_equal @issue1, Journal.last.journalized
      errors = ir.errors.generate_message(:anchor_to_start, :start_mode_requires_date)
      msg = "#{I18n.t(:warning_renew, id: ref_issue.id, errors: errors)}\r\n"
      assert_equal msg, Journal.last.notes

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
      assert_equal @issue1, Journal.last.journalized
      errors = ir.errors.generate_message(:anchor_to_start, :due_mode_requires_date)
      msg = "#{I18n.t(:warning_renew, id: ref_issue.id, errors: errors)}\r\n"
      assert_equal msg, Journal.last.notes

      destroy_recurrence(ir)
    end
  end

  def test_renew_logs_warning_for_creation_mode_reopen_wo_subtasks_after_child_added
    @issue1.update!(start_date: Date.new(2018,9,15), due_date: nil)

    # No children, recur w/o subtasks, dates derived = should recur
    Setting.parent_issue_dates = 'derived'
    assert_equal [], @issue1.children
    ir = create_recurrence(
      anchor_to_start: true,
      anchor_mode: :last_issue_flexible,
      creation_mode: :reopen,
      include_subtasks: false
    )

    travel_to(Date.new(2018,9,15))
    close_issue(@issue1)
    renew_all(0)
    [@issue1, @issue2].map(&:reload)
    assert_equal Date.new(2018,9,22), @issue1.start_date
    assert_not @issue1.closed?


    # 1 child, recur w/o subtasks, dates derived = should NOT recur
    @issue2.update!(start_date: Date.new(2018,9,29), due_date: nil)
    set_parent_issue(@issue1, @issue2)
    [@issue1, @issue2].map(&:reload)
    assert_equal Date.new(2018,9,29), @issue1.start_date

    travel_to(Date.new(2018,12,2))
    close_issue(@issue2)
    close_issue(@issue1)
    assert_difference 'Journal.count', 1 do
      renew_all(0)
    end
    [@issue1, @issue2].map(&:reload)
    assert_equal @issue1, Journal.last.journalized
    errors = ir.errors
      .generate_message(:creation_mode, :derived_dates_reopen_requires_subtasks)
    msg = "#{I18n.t(:warning_renew, id: @issue1.id, errors: errors)}\r\n"
    assert_equal msg, Journal.last.notes
    assert_equal Date.new(2018,9,29), @issue1.start_date
    assert @issue1.closed?


    # 1 child, recur w/o subtasks, dates independent = should recur
    Setting.parent_issue_dates = 'independent'
    renew_all(0)
    [@issue1, @issue2].map(&:reload)
    assert_equal Date.new(2018,12,9), @issue1.start_date
    assert_not @issue1.closed?
    assert @issue2.closed?


    # 1 child, recur w/ subtasks, dates derived = should recur
    Setting.parent_issue_dates = 'derived'
    [@issue1, @issue2].map(&:reload)
    assert_equal Date.new(2018,12,9), @issue1.start_date
    assert_equal Date.new(2018,9,29), @issue2.start_date
    update_recurrence(ir, include_subtasks: true)
    travel_to(Date.new(2019,1,10))
    assert @issue2.closed?
    close_issue(@issue1)
    renew_all(0)
    [@issue1, @issue2].map(&:reload)
    assert_equal Date.new(2018,11,7), @issue1.start_date
    assert_equal Date.new(2018,11,7), @issue2.start_date
    assert_not @issue1.closed?
    assert_not @issue2.closed?
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
