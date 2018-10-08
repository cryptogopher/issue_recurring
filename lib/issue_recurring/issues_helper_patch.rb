module IssueRecurring
  module IssuesHelperPatch
    IssuesHelper.class_eval do
      def creation_mode_options
        translations = t('.creation_modes')
        IssueRecurrence.creation_modes.map do |k,v|
          [sanitize(translations[k.to_sym], tags:{}), k]
        end
      end

      def mode_options
        translations = t('.modes')
        IssueRecurrence.modes.map do |k,v|
          [sanitize(translations[k.to_sym], tags:{}), k]
        end
      end

      def anchor_mode_options
        dates = {start: @issue.start_date, due: @issue.due_date}
        options = IssueRecurrence.anchor_modes.map do |k,v|
          [sanitize(t(".anchor_modes.#{k}", dates), tags:{}), k]
        end
        selected = issue_start_date.present? ? [:first_issue_fixed] : [:last_issue_fixed]
        disabled = issue_start_date.blank? ? [:first_issue_fixed] : []
        [options, selected, disabled]
      end

      def issue_start_date
        @issue.start_date || @issue.due_date
      end

      def last_recurrence(r)
        s = "#{t ".last_recurrence"} "
        if r.last_issue.present?
          s += "#{link_to("##{r.last_issue.id}", issue_path(r.last_issue)) }" \
            "#{r.last_date.start_date} - #{r.last_date.due_date}"
        else
          s += "-"
        end
        s.html_safe
      end

      def next_recurrence_date(r)
        "#{t ".next_recurrence"} " \
          "#{"#{r.next[:start]}" if r.next[:start]}" \
          " -" \
          " #{"#{r.next[:due]}" if r.next[:due]}".html_safe
      end
    end
  end
end

