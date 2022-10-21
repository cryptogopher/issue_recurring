# Load Redmine patches before plugin registration
# NOTE: simplify when Rails < 6 no longer supported and there is only Zeitwerk
def load_patches
  Issue.include IssueRecurring::IssuePatch
  IssuesController.include IssueRecurring::IssuesControllerPatch
  IssuesHelper.include IssueRecurring::IssuesHelperPatch

  Project.include IssueRecurring::ProjectPatch

  SettingsController.include IssueRecurring::SettingsControllerPatch
  SettingsHelper.include IssueRecurring::SettingsHelperPatch

  ActiveRecord::Schema.prepend IssueRecurring::SchemaPatch
  ActiveRecord::SchemaDumper.prepend IssueRecurring::SchemaDumperPatch
end

if Rails.respond_to?(:autoloaders) && Rails.autoloaders.zeitwerk_enabled?
  IssueRecurring::IssueRecurrencesViewListener
  load_patches
else
  require_dependency 'issue_recurring/issue_recurrences_view_listener'
  ActiveSupport::Reloader.to_prepare { load_patches }
end


Redmine::Plugin.register :issue_recurring do
  name 'Issue recurring plugin'
  author 'cryptogopher'
  description 'Schedule Redmine issue recurrence based on multiple conditions'
  version '1.7'
  url 'https://github.com/cryptogopher/issue_recurring'
  author_url 'https://github.com/cryptogopher'

  project_module :issue_recurring do
    permission :view_issue_recurrences, {:issue_recurrences => [:index]},
      read: true
    permission :manage_issue_recurrences, {:issue_recurrences => [:create, :destroy]},
      require: :loggedin
  end
  menu :project_menu, :issue_recurrences,
    {:controller => 'issue_recurrences', :action => 'index'},
    :caption => :issue_recurrences_menu_caption,
    :after => :issues, :param => :project_id

  settings default: {
    author_login: nil,
    keep_assignee: false,
    journal_mode: :never,
    ahead_multiplier: 0,
    ahead_mode: :days
  }, partial: 'settings/issue_recurrences'
end
