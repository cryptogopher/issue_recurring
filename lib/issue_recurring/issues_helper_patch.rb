module IssueRecurring
  module IssuesHelperPatch
    IssuesHelper.class_eval do
      def creation_mode_options
        options = t('issues.recurrences.form.creation_modes')
        IssueRecurrence.creation_modes.map { |k,v| [options[k.to_sym], v] }
      end

      def mode_options
        options = t('issues.recurrences.form.modes')
        IssueRecurrence.modes.map { |k,v| [options[k.to_sym], v] }
      end

      def issue_start_date
        @issue.start_date || @issue.due_date
      end
    end
  end
end

