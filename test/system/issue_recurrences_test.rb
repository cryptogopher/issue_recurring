require_relative '../application_system_test_case'

class IssueRecurrencesSystemTest < IssueRecurringSystemTestCase
  def setup
    super

    Setting.non_working_week_days = [6, 7]
    Setting.parent_issue_dates = 'derived'
    Setting.parent_issue_priority = 'derived'
    Setting.parent_issue_done_ratio = 'derived'
    Setting.issue_done_ratio == 'issue_field'

    # FIXME: settings should be set through controller by admin user
    # (log_user/logout_user)
    Setting.plugin_issue_recurring = {
      author_id: 0,
      keep_assignee: false,
      journal_mode: :never,
      copy_recurrences: true,
      ahead_multiplier: 0,
      ahead_mode: :days
    }

    @project1 = projects(:project_01)
    @issue1 = issues(:issue_01)
    @issue2 = issues(:issue_02)
    @issue3 = issues(:issue_03)

    log_user 'alice', 'foo'
  end

  def teardown
    logout_user
    super
  end

  def test_create_recurrence
    @issue1.update!(random_dates)

    # Verify that every valid random recurrence can be entered into form
    create_recurrence

    # Verify that every recurrence that can be entered into form is valid.
    # Implicitly tests form fields hiding depending on recurrence setting selection.
    create_recurrence { fill_in_randomly }
  end

  def test_update_recurrence
    @issue1.update!(random_dates)
    r = create_recurrence

    # Verify that every valid random update can be entered into form
    update_recurrence r

    # Verify that every update that can be entered into form is valid
    update_recurrence r { fill_in_randomly }

    # Verify that update with no change yields the same recurrence
    assert_no_changes 'r.reload.attributes' do
      update_recurrence r { }
    end
  end

  def test_destroy_recurrence
    @issue1.update!(random_dates)
    destroy_recurrence(create_recurrence)
  end

  def test_show_issue_recurrences
    # TODO: randomize # of recurrences 0..N
    visit issue_path(@issue1)
    within_issue_recurrences_panel do
      assert_equal @issue1.recurrences.count, all("tr").length
    end
  end

  def test_show_issue_shows_recurrence_form_only_when_manage_permission_granted
    logout_user
    log_user 'bob', 'foo'

    roles = users(:bob).members.find_by(project: @issue1.project_id).roles
    assert roles.any? { |role| role.has_permission? :manage_issue_recurrences }
    visit issue_path(@issue1)
    assert_current_path issue_path(@issue1)
    within_issue_recurrences_panel do
      assert_selector 'a', text: t(:button_add)
      assert_no_selector 'form#recurrence-form'
      click_link t(:button_add)
      assert_selector 'form#recurrence-form'
    end

    roles.each { |role| role.remove_permission! :manage_issue_recurrences }
    refute roles.any? { |role| role.has_permission? :manage_issue_recurrences }
    visit issue_path(@issue1)
    assert_current_path issue_path(@issue1)
    within_issue_recurrences_panel do
      assert_no_selector 'a', text: t(:button_add)
      assert_no_selector 'form#recurrence-form'
    end
  end

  def test_settings_author_login
    @issue1.update!(start_date: 10.days.ago, due_date: 5.days.ago)
    create_recurrence(creation_mode: :copy_first)
    logout_user

    log_user 'admin', 'foo'
    visit plugin_settings_path(id: 'issue_recurring')
    t_base = 'settings.issue_recurrences'
    author_select = t("#{t_base}.author")

    select t("#{t_base}.author_unchanged"), from: author_select
    click_button t(:button_apply)
    assert_selector '#flash_notice', exact_text: t(:notice_successful_update)
    assert_nil Setting.plugin_issue_recurring[:author_login]
    assert has_select?(author_select, selected: t("#{t_base}.author_unchanged"))

    travel_to(@issue1.start_date)
    r1 = renew_all(1)
    assert_equal users(:bob), @issue1.author
    assert_equal users(:bob), r1.author

    select users(:charlie).name, from: author_select
    click_button t(:button_apply)
    assert_selector '#flash_notice', exact_text: t(:notice_successful_update)
    assert_equal users(:charlie).login, Setting.plugin_issue_recurring[:author_login]
    assert has_select?(author_select, selected: users(:charlie).name)

    travel_to(r1.start_date)
    r2 = renew_all(1)
    assert_equal users(:bob), @issue1.author
    assert_equal users(:charlie), r2.author
  end

  def test_settings_keep_assignee
    assert_not_equal @issue1.assigned_to, @issue1.project.default_assigned_to
    @issue1.update!(start_date: 10.days.ago, due_date: 5.days.ago)
    create_recurrence(creation_mode: :copy_first)
    logout_user

    log_user 'admin', 'foo'
    visit plugin_settings_path(id: 'issue_recurring')
    keep_assignee_checkbox = t('settings.issue_recurrences.keep_assignee')

    uncheck keep_assignee_checkbox
    click_button t(:button_apply)
    assert_selector '#flash_notice', exact_text: t(:notice_successful_update)
    assert_equal false, Setting.plugin_issue_recurring[:keep_assignee]
    assert has_unchecked_field?(keep_assignee_checkbox)

    travel_to(@issue1.start_date)
    r1 = renew_all(1)
    assert_equal users(:gopher), @issue1.project.default_assigned_to
    assert_equal users(:gopher), r1.assigned_to

    check keep_assignee_checkbox
    click_button t(:button_apply)
    assert_selector '#flash_notice', exact_text: t(:notice_successful_update)
    assert_equal true, Setting.plugin_issue_recurring[:keep_assignee]
    assert has_checked_field?(keep_assignee_checkbox)

    travel_to(r1.start_date)
    r2 = renew_all(1)
    assert_equal users(:alice), @issue1.assigned_to
    assert_equal users(:alice), r2.assigned_to
  end

  def test_settings_journal_mode
    @issue1.update!(start_date: 10.days.ago, due_date: 5.days.ago)
    @issue2.update!(start_date: 10.days.ago, due_date: 5.days.ago)

    ir1 = create_recurrence(issue: @issue1,
                            creation_mode: :copy_first, anchor_to_start: true,
                            anchor_mode: :last_issue_fixed)
    ir2 = create_recurrence(issue: @issue2,
                            creation_mode: :reopen, anchor_to_start: true,
                            anchor_mode: :last_issue_flexible)
    logout_user
    log_user 'admin', 'foo'

    configs = [
      {mode: :never, journalized: []},
      {mode: :always, journalized: [@issue1, @issue2]},
      {mode: :on_reopen, journalized: [@issue2]}
    ]

    t_base = 'settings.issue_recurrences'
    journal_mode_select = t("#{t_base}.journal_mode")

    configs.each do |config|
      visit plugin_settings_path(id: 'issue_recurring')

      value = t("#{t_base}.journal_modes.#{config[:mode]}")
      select value, from: journal_mode_select
      click_button t(:button_apply)
      assert_selector '#flash_notice', exact_text: t(:notice_successful_update)
      assert_equal config[:mode], Setting.plugin_issue_recurring[:journal_mode]
      assert has_select?(journal_mode_select, selected: value)

      assert_equal (ir1.last_issue || @issue1).start_date, @issue2.start_date
      travel_to(@issue2.start_date)
      close_issue(@issue2)
      count = config[:journalized].length
      r2 = assert_difference 'Journal.count', count do renew_all(1) end
      [ir1, @issue1, @issue2].map(&:reload)
      assert !@issue2.closed?
      if count > 0
        assert_equal config[:journalized], Journal.last(count).map(&:journalized)
        assert_equal config[:journalized].map(&:author), Journal.last(count).map(&:user)
      end
    end
  end

  def test_settings_copy_recurrences
    # TODO: migrate integration test_renew_applies_copy_recurrences_configuration_setting
  end

  def test_settings_renew_ahead
    @issue1.update!(start_date: Date.new(2020,7,12), due_date: Date.new(2020,7,17))

    logout_user
    log_user 'admin', 'foo'

    t_mode_base = 'issues.recurrences.form.delay_modes'
    label_text = t('settings.issue_recurrences.renew_ahead')

    set_renew_ahead = -> (multiplier, mode) {
      input_value = multiplier.to_s
      select_value = t("#{t_mode_base}.#{mode}")

      visit plugin_settings_path(id: 'issue_recurring')
      within(find('label', exact_text: label_text).ancestor('p')) do
        fill_in with: input_value
        select select_value
      end

      click_button t(:button_apply)
      assert_selector '#flash_notice', exact_text: t(:notice_successful_update)
      assert_equal multiplier, Setting.plugin_issue_recurring[:ahead_multiplier]
      assert_equal mode, Setting.plugin_issue_recurring[:ahead_mode]

      within(find('label', exact_text: label_text).ancestor('p')) do
        assert has_field?(type: 'number', with: input_value)
        assert has_select?(selected: select_value)
      end
    }

    [:first_issue_fixed, :last_issue_fixed].each do |am|
      ir = create_recurrence(creation_mode: :copy_first, mode: :weekly, anchor_mode: am)

      set_renew_ahead.(6, :days)
      travel_to(@issue1.start_date - 1.week)
      renew_all(0)

      set_renew_ahead.(1, :weeks)
      r1 = renew_all(1)
      assert_equal Date.new(2020,7,19), r1.start_date
      assert_equal Date.new(2020,7,24), r1.due_date

      set_renew_ahead.(1, :months)
      rest = renew_all(3)
      assert_equal [Date.new(2020,7,26), Date.new(2020,8,2), Date.new(2020,8,9)],
        rest.map(&:start_date)
      assert_equal [Date.new(2020,7,31), Date.new(2020,8,7), Date.new(2020,8,14)],
        rest.map(&:due_date)

      set_renew_ahead.(0, :months)
      travel_to(rest.last.start_date - 1.day)
      renew_all(0)

      destroy_recurrence(ir)
    end
  end
end
