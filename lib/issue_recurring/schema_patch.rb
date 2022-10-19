# NOTE: remove when https://www.redmine.org/issues/37803 is fixed
module IssueRecurring
  module SchemaPatch
    ActiveRecord::ConnectionAdapters::SchemaStatements.class_eval do
      def assume_plugin_migrated_upto_version(plugin_id, version)
        plugin = Redmine::Plugin.find(plugin_id)
        version = version.to_i

        migrated = Redmine::Plugin::Migrator.get_all_versions(plugin)
        versions = plugin.migrations
        inserting = (versions - migrated).select { |v| v <= version }
        if inserting.any?
          schema_migration.create_table
          execute insert_versions_sql(inserting.map! { |v| "#{v}-#{plugin_id}" })
        end
      end
    end

    # TODO: replace arguments with argument forwarding (info, ...) in Ruby 3.0
    def define(info, &block)
      super
      info.except(:version).each { |id, v| assume_plugin_migrated_upto_version(id, v) }
    end
  end
end
