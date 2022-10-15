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
  end

  def test_migrate_empty_database
    migrate 0
    migrate @plugin.latest_migration
  end

  class IssueRecurrence < ActiveRecord::Base
  end

  def test_migrate_with_recurrences_present
    migrate 1
    # Fixed schedule, every 1 week
    #IssueRecurrence.reset_column_information
    ir = IssueRecurrence.new(issue_id: @issue1.id, anchor_mode: 0, mode: 100, multiplier: 1)
    ir.save!
    migrate @plugin.latest_migration
  end
end
