module IssueRecurring
  module IssuesHelperPatch
    IssuesHelper.class_eval do
      def creation_mode_options
        translations = t('.creation_modes')
        IssueRecurrence.creation_modes.map { |k,v| [translations[k.to_sym], k] }
      end

      def mode_options
        translations = t('.modes')
        IssueRecurrence.modes.map { |k,v| [translations[k.to_sym], k] }
      end

      def anchor_mode_options
        dates = {start_date: @issue.start_date, due_date: @issue.due_date}
        options = IssueRecurrence.anchor_modes.map do |k,v|
          [t(".anchor_modes.#{k}", dates), k]
        end
        selected = issue_start_date.present? ? [:first_issue_fixed] : [:last_issue_fixed]
        disabled = issue_start_date.blank? ? [:first_issue_fixed] : []
        [options, selected, disabled]
      end

      def issue_start_date
        @issue.start_date || @issue.due_date
      end
    end
  end
end

