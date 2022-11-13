module LoadIssueRecurrences
  extend ActiveSupport::Concern

  def load_issue_recurrences(reload: false)
    @issue.recurrences.reload if reload
    @recurrences = @issue.recurrences.select {|r| r.visible?}
    @next_dates = IssueRecurrence.issue_dates(@issue)
    @predicted_dates = IssueRecurrence.issue_dates(@issue, true)
  end
end
