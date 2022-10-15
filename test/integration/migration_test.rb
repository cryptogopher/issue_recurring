require_relative '../test_helper'

class MigrationsTest < IssueRecurringIntegrationTestCase
  self.use_transactional_tests = false

  # NOTE: remove when https://www.redmine.org/issues/31116 is fixed
  Redmine::Plugin::MigrationContext.class_eval do
    def current_version
      Redmine::Plugin::Migrator.current_version
    end
  end

  def migrate(version)
    # Force refresh of schema_migration state
    Redmine::Plugin::Migrator.instance_variable_get(:@all_versions)
      &.delete('issue_recurring')

    ActiveRecord::Migration.suppress_messages do
      Redmine::Plugin.migrate('issue_recurring', version)
    end
  end

  def setup
    super

    @plugin = Redmine::Plugin.find('issue_recurring')
    @issue1 = issues(:issue_01)
    @issue2 = issues(:issue_02)
  end

  class IssueRecurrence < ActiveRecord::Base
  end

  def test_migrate_with_no_recurrences
    assert IssueRecurrence.count, 0
    migrate 0
    migrate @plugin.latest_migration
  end

  def test_migrate_with_recurrences_present
    migrate 1
    # Fixed schedule, every 1 week
    ir = IssueRecurrence.new(issue_id: @issue1.id, anchor_mode: 0, mode: 100, multiplier: 1)
    assert_difference 'IssueRecurrence.count', 1 do
      ir.save!
    end
    assert_no_difference 'IssueRecurrence.count' do
      migrate @plugin.latest_migration
    end
  end

  def test_migration_003
    migrate 2

    # Fixed schedule, monthly, day to last day of month based on start date
    ir1 = IssueRecurrence
      .new(issue_id: @issue1.id, anchor_mode: 0, mode: 210, multiplier: 1)

    # Flexible schedule, weekly, only due date present
    @issue2.update!(due_date: Date.current)
    assert_nil @issue2.start_date
    ir2 = IssueRecurrence
      .new(issue_id: @issue2.id, anchor_mode: 2, mode: 100, multiplier: 1)

    assert_difference 'IssueRecurrence.count', 2 do
      [ir1, ir2].map(&:save!)
    end

    assert_no_difference 'IssueRecurrence.count' do
      migrate 3
    end
    [ir1, ir2].map(&:reload)

    assert_equal ir1.mode, 212
    assert_equal ir1.anchor_to_start, 1
    assert_equal ir2.mode, 100
    assert_equal ir2.anchor_to_start, 0

    assert_no_difference 'IssueRecurrence.count' do
      migrate 2
    end
    [ir1, ir2].map(&:reload)

    assert_equal ir1.mode, 210
    assert_not ir1.has_attribute?(:anchor_to_start)
    assert_equal ir2.mode, 100
    assert_not ir2.has_attribute?(:anchor_to_start)
  end
end
