require File.expand_path('../../application_system_test_case', __FILE__)

class IssueRecurrencesTest < IssueRecurringSystemTestCase
  def setup
    super

    Setting.non_working_week_days = [6, 7]

    # FIXME: settings should be set through controller by admin user
    Setting.plugin_issue_recurring = {
      author_id: 0,
      keep_assignee: false,
      journal_mode: :never,
      copy_recurrences: true
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

  def test_show_issue_recurrences
    visit issue_path(@issue1)
  end

  def test_settings_author_id
    @issue1.update!(start_date: 10.days.ago, due_date: 5.days.ago)
    create_recurrence(creation_mode: :copy_first)
    logout_user

    log_user 'admin', 'foo'
    visit plugin_settings_path(id: 'issue_recurring')
    t_base = 'settings.issue_recurrences'

    select t("#{t_base}.author_unchanged"), from: t("#{t_base}.author")
    click_button t(:button_apply)
    assert_text '#flash_notice', t(:notice_successful_update)
    assert_equal 0, Setting.plugin_issue_recurring[:author_id]

    travel_to(@issue1.start_date)
    r1 = renew_all(1)
    assert_equal users(:bob), @issue1.author
    assert_equal users(:bob), r1.author

    select users(:charlie).name, from: t("#{t_base}.author")
    click_button t(:button_apply)
    assert_text '#flash_notice', t(:notice_successful_update)
    assert_equal users(:charlie).id, Setting.plugin_issue_recurring[:author_id]

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

    uncheck t('settings.issue_recurrences.keep_assignee')
    click_button t(:button_apply)
    assert_text '#flash_notice', t(:notice_successful_update)
    assert_equal false, Setting.plugin_issue_recurring[:keep_assignee]

    travel_to(@issue1.start_date)
    r1 = renew_all(1)
    assert_equal users(:gopher), @issue1.project.default_assigned_to
    assert_equal users(:gopher), r1.assigned_to

    check t('settings.issue_recurrences.keep_assignee')
    click_button t(:button_apply)
    assert_text '#flash_notice', t(:notice_successful_update)
    assert_equal true, Setting.plugin_issue_recurring[:keep_assignee]

    travel_to(r1.start_date)
    r2 = renew_all(1)
    assert_equal users(:alice), @issue1.assigned_to
    assert_equal users(:alice), r2.assigned_to
  end

  def test_settings_journal_mode
    @issue1.update!(start_date: 10.days.ago, due_date: 5.days.ago)
    @issue2.update!(start_date: 10.days.ago, due_date: 5.days.ago)
    ir1 = create_recurrence(@issue1, creation_mode: :copy_first, anchor_to_start: true,
                           anchor_mode: :last_issue_fixed)
    ir2 = create_recurrence(@issue2, creation_mode: :in_place, anchor_to_start: true,
                            anchor_mode: :last_issue_flexible)
    logout_user
    log_user 'admin', 'foo'

    configs = [
      {mode: :never, journalized: []},
      {mode: :always, journalized: [@issue1, @issue2]},
      {mode: :in_place, journalized: [@issue2]}
    ]

    configs.each do |config|
      visit plugin_settings_path(id: 'issue_recurring')
      select t("settings.issue_recurrences.journal_modes.#{config[:mode]}"),
        from: t('settings.issue_recurrences.journal_mode')
      click_button t(:button_apply)
      assert_text '#flash_notice', t(:notice_successful_update)
      assert_equal config[:mode], Setting.plugin_issue_recurring[:journal_mode]

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
    # TODO: migrate integrtion test_renew_applies_copy_recurrences_configuration_setting
  end
end
