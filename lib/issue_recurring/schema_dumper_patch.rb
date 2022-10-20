# NOTE: remove when https://www.redmine.org/issues/37803 is fixed
module IssueRecurring
  module SchemaDumperPatch
    def define_params
      versions = super.present? ? [super] : []
      Redmine::Plugin.all.each do |plugin|
        current_migration = Redmine::Plugin::Migrator.current_version(plugin)
        versions << "#{plugin.id}: #{current_migration}" if current_migration > 0
      end
      versions.join(", ")
    end
  end
end
