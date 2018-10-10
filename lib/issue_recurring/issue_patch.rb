module IssueRecurring
  module IssuePatch
    Issue.class_eval do
      has_many :recurrences, class_name: 'IssueRecurrence', dependent: :destroy

      belongs_to :recurrence_of, class_name: 'Issue'
      has_many :recurrence_copies, class_name: 'Issue', foreign_key: 'recurrence_of_id',
        dependent: :nullify

      validates :recurrence_of, associated: true
    end
  end
end

