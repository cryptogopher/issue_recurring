module IssueRecurring
  module IssuePatch
    Issue.class_eval do
      has_many :recurrences, class_name: 'IssueRecurrence', dependent: :destroy
      has_one :source_recurrence, class_name: 'IssueRecurrence', dependent: :nullify,
        foreign_key: :last_issue
    end
  end
end

