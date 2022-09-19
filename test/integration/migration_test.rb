require_relative '../test_helper'

class MigrationsTest < Redmine::IntegrationTest
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
    @plugin = Redmine::Plugin.find('issue_recurring')
  end

  def test_migrate_empty_database
    migrate 0
    migrate @plugin.latest_migration
  end
end
