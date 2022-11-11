# Load Redmine patches before plugin registration
# NOTE: simplify when Rails < 6 no longer supported and there is only Zeitwerk
def load_patches
  # include()/prepend() assures that each patch is applied only once.
  # If the class has been included somewhere else prior to patching, it has to
  # be patched in place with class_eval() instead of mere patch inclusion.
  # This is because include()'d patch won't be reflected in ancestor structure
  # in place of previous inclusions. This is immanent feature of Ruby:
  # '[...] the reason for this, [...] was performance. Ancestor chains are
  # linearized, and if you add a new ancestor to a module, Ruby does not update
  # the linearized cached ancestor chains of the affected existing classes or
  # modules [that have included eariler the module with later-added ancestor].
  # Ruby does not keep backreferences registering "where was this module included'.
  # https://github.com/hotwired/turbo-rails/issues/64#issuecomment-778601827

  # NOTE: remove when https://www.redmine.org/issues/37803 is fixed
  ActiveRecord::ConnectionAdapters::SchemaStatements
    .include IssueRecurring::SchemaStatementsPatch
  ActiveRecord::Schema.prepend IssueRecurring::SchemaPatch
  ActiveRecord::SchemaDumper.prepend IssueRecurring::SchemaDumperPatch

  Issue.include IssueRecurring::IssuePatch
  # Helper module has to be patched before Controller is loaded. Loading
  # Controller causes Helper module to be loaded and included. Any subsequent
  # inclusions (i.e. change in ancestor chain) in Helper module won't be
  # reflected in Controller's ancestor structure.
  IssuesHelper.include IssueRecurring::IssuesHelperPatch
  IssuesController.include IssueRecurring::IssuesControllerPatch

  Project.include IssueRecurring::ProjectPatch

  SettingsHelper.include IssueRecurring::SettingsHelperPatch
  SettingsController.include IssueRecurring::SettingsControllerPatch
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
    copy_recurrences: false,
    ahead_multiplier: 0,
    ahead_mode: :days
  }, partial: 'settings/issue_recurrences'
end
