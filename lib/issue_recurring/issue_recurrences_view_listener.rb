module IssueRecurring
  class IssueRecurrencesViewListener < Redmine::Hook::ViewListener
    render_on :view_issues_show_description_bottom, partial: 'issues/issue_recurrences_hook'
  end
end
