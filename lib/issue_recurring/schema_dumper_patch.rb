# NOTE: remove when https://www.redmine.org/issues/37803 is fixed
module IssueRecurring
  module SchemaDumperPatch
    def define_params
      versions = super.present? ? [super] : []
      Redmine::Plugin.all.each do |plugin|
        versions << "#{plugin.id}: #{plugin.latest_migration}" if plugin.latest_migration
      end
      versions.join(", ")
    end
  end
end
