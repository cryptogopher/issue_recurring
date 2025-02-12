module LoadIssueRecurrences
  extend ActiveSupport::Concern

  def load_issue_recurrences(reload: false)
    @issue.issue_recurrences.reload if reload
    @recurrences = @issue.issue_recurrences.select {|r| r.visible?}
    @next_dates = IssueRecurrence.issue_dates(@issue)
    @predicted_dates = IssueRecurrence.issue_dates(@issue, true)
  end
end
