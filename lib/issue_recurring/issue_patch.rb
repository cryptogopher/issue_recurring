module IssueRecurring
  module IssuePatch
    Issue.class_eval do
      has_many :recurrences, class_name: 'IssueRecurrence', dependent: :destroy

      belongs_to :recurrence_of, class_name: 'Issue'
      has_many :recurrence_copies, class_name: 'Issue', foreign_key: 'recurrence_of_id',
        dependent: :nullify

      validates :recurrence_of, associated: true, unless: "recurrence_of == self"

      after_destroy :substitute_if_last_issue

      def substitute_if_last_issue
        return if self.recurrence_of.blank?
        r = self.recurrence_of.recurrences.find_by(last_issue: self)
        return if r.nil?
        r.update!(last_issue: r.issue.recurrence_copies.last)
      end

      def default_reassign
        self.assigned_to = nil
        default_assign
      end
    end
  end
end

