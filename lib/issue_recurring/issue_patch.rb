module IssueRecurring
  module IssuePatch
    extend ActiveSupport::Concern

    included do
      include InstanceMethods

      has_many :recurrences, class_name: 'IssueRecurrence', dependent: :destroy

      belongs_to :recurrence_of, class_name: 'Issue', validate: true
      has_many :recurrence_copies, class_name: 'Issue', foreign_key: 'recurrence_of_id',
        dependent: :nullify

      after_destroy :substitute_if_last_issue

      alias_method :copy_from_without_recurrences, :copy_from
      alias_method :copy_from, :copy_from_with_recurrences
    end

    module InstanceMethods
      def copy_from_with_recurrences(arg, options={})
        copy_from_without_recurrences(arg, options)

        unless options[:skip_recurrences]
          self.recurrence_of = nil

          if Setting.plugin_issue_recurring[:copy_recurrences]
            self.recurrences = @copied_from.recurrences.map(&:dup)
          end
        end

        self
      end

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
