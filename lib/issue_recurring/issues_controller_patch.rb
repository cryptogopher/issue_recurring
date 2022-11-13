module IssueRecurring
  module IssuesControllerPatch
    IssuesController.class_eval do
      include LoadIssueRecurrences

      before_action :load_issue_recurrences, only: [:show]
    end
  end
end
