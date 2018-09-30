module IssueRecurring
  module IssuePatch
    Issue.class_eval do
      has_many :recurrences, class_name: 'IssueRecurrence', dependent: :destroy
    end
  end
end

