module IssueRecurring
  module IssuesHelperPatch
    IssuesHelper.class_eval do
      def creation_mode_options
        translations = t('.creation_modes')
        options = IssueRecurrence.creation_modes.map do |k,v|
          [sanitize(translations[k.to_sym], tags:{}), k]
        end
        disabled = @recurrence.fixed? ? [:in_place] : []
        [options, disabled]
      end

      def mode_options
        translations = t('.modes')
        options = IssueRecurrence.modes.map do |k,v|
          [sanitize(translations[k.to_sym], tags:{}), k]
        end

        disabled = []
        disabled = IssueRecurrence::START_MODES if @issue.start_date.blank?
        disabled += IssueRecurrence::DUE_MODES if @issue.due_date.blank?

        [options, disabled]
      end

      def anchor_mode_options
        issue_has_date = (@issue.start_date || @issue.due_date).present?
        options = IssueRecurrence.anchor_modes.map do |k,v|
          next if !issue_has_date && IssueRecurrence::FIXED_MODES.include?(k)
          [sanitize(t(".anchor_modes.#{k}"), tags:{}), k]
        end
        options.compact!

        disabled = []
        disabled = IssueRecurrence::FIXED_MODES if @recurrence.creation_mode == 'in_place'
        disabled += IssueRecurrence::FLEXIBLE_MODES if @recurrence.delay_multiplier > 0

        [options, disabled]
      end

      def delay_mode_options
        translations = t('.delay_modes')
        IssueRecurrence.delay_modes.map do |k,v|
          [translations[k.to_sym], k]
        end
      end

      def last_recurrence(r, intro=true)
        s = intro ? "#{t ".last_recurrence"} " : ""
        if r.last_issue.present?
          s += "#{link_to("##{r.last_issue.id}", issue_path(r.last_issue)) }" \
            "#{r.last_issue.start_date} - #{r.last_issue.due_date}"
        else
          s += "-"
        end
        s.html_safe
      end

      def next_recurrence_date(r, intro=true)
        next_dates = r.next_dates || {}
        "#{"#{t ".next_recurrence"} " if intro}" \
          "#{next_dates[:start]} - #{next_dates[:due]}".html_safe
      end

      def delete_button(r)
        link_to l(:button_delete), recurrence_path(r), method: :delete, remote: true,
          class: 'icon icon-del' if r.editable?
      end
    end
  end
end

