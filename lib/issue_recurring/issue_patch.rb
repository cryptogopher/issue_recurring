module IssueRecurring
  module CopyFromWithRecurrences
    def copy_from(arg, options={})
      super

      unless options[:skip_recurrences]
        self.recurrence_of = nil

        if Setting.plugin_issue_recurring[:copy_recurrences]
          self.issue_recurrences = @copied_from.issue_recurrences.map(&:dup)
        end
      end

      self
    end
  end

  module IssuePatch
    Issue.class_eval do
      prepend CopyFromWithRecurrences

      has_many :issue_recurrences, dependent: :destroy

      # Do not set :recurrence_of for:
      # * descendants of recurred Issue. Otherwise it will be impossible to
      #   determine last recurrence in the chain (IssueRecurrence#last_issue)
      #   after the current last is deleted. Recurred descendants tracking is
      #   not needed at this point.
      # * owner of IssueRecurrence. It would not work with multiple recurrence
      #   schemes.
      # * both of the above apply to :reopen recurrences as well.
      # Value of :recurrence_of is independent of 'recurs_in' IssueRelation.
      belongs_to :recurrence_of, class_name: 'IssueRecurrence', validate: true
    end

    def default_reassign
      self.assigned_to = nil
      default_assign
    end
  end
end

