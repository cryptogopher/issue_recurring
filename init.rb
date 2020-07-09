require_dependency 'issue_recurring/issue_recurrences_view_listener'

(Rails::VERSION::MAJOR < 5 ? ActionDispatch : ActiveSupport)::Reloader.to_prepare do
  Issue.include IssueRecurring::IssuePatch
  IssuesController.include IssueRecurring::IssuesControllerPatch
  IssuesHelper.include IssueRecurring::IssuesHelperPatch

  Project.include IssueRecurring::ProjectPatch

  Setting.singleton_class.prepend IssueRecurring::SettingPatch
  SettingsController.include IssueRecurring::SettingsControllerPatch
  SettingsHelper.include IssueRecurring::SettingsHelperPatch
end

Redmine::Plugin.register :issue_recurring do
  name 'Issue recurring plugin'
  author 'cryptogopher'
  description 'Schedule Redmine issue recurrence based on multiple conditions'
  version '1.6'
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
    journal_mode: :never
  }, partial: 'settings/issue_recurrences'
end
