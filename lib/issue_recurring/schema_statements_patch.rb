module IssueRecurring
  module SchemaStatementsPatch
    ActiveRecord::ConnectionAdapters::SchemaStatements.class_eval do
      def assume_plugin_migrated_upto_version(plugin_id, version)
        plugin = Redmine::Plugin.find(plugin_id)
        version = version.to_i

        migrated = Redmine::Plugin::Migrator.get_all_versions(plugin)
        versions = plugin.migrations
        inserting = (versions - migrated).select { |v| v <= version }
        if inserting.any?
          ActiveRecord::SchemaMigration.create_table
          execute insert_versions_sql(inserting.map! { |v| "#{v}-#{plugin_id}" })
        end
      end
    end
  end
end
