require_dependency 'issue_recurrence_plugin/issue_recurrences_view_listener'

ActionDispatch::Reloader.to_prepare do
  Issue.include IssueRecurrencePlugin::IssuePatch
  IssuesController.include IssueRecurrencePlugin::IssuesControllerPatch
end

Redmine::Plugin.register :issue_recurrence do
  name 'Issue recurrence plugin'
  author 'cryptogopher'
  description 'Schedule Redmine issue recurrence based on multiple conditions'
  version '0.0.1'
  url 'https://github.com/cryptogopher/issue_recurrence'
  author_url 'https://github.com/cryptogopher'

  project_module :issue_tracking do
    permission :manage_issue_recurrences, {:issue_recurrences => [:create, :destroy]}
  end
end
