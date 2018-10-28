module IssueRecurring
  module IssuePatch
    Issue.class_eval do
      has_many :recurrences, class_name: 'IssueRecurrence', dependent: :destroy

      belongs_to :recurrence_of, class_name: 'Issue'
      has_many :recurrence_copies, class_name: 'Issue', foreign_key: 'recurrence_of_id',
        dependent: :nullify

      validates :recurrence_of, associated: true, unless: "recurrence_of == self"

      def default_reassign
        self.assigned_to = nil
        default_assign
      end
    end
  end
end

