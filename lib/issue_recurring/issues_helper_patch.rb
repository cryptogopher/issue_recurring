module IssueRecurring
  module IssuesHelperPatch
    IssuesHelper.class_eval do
      def creation_mode_options
        translations = t('.creation_modes')
        IssueRecurrence.creation_modes.map do |k,v|
          [sanitize(translations[k.to_sym], tags:{}), k]
        end
      end

      def include_subtasks_options
        [true, false].map do |v|
          [sanitize(t(".include_subtasks.#{v}"), tags:{}), v]
        end
      end

      def mode_options
        intervals = t('.mode_intervals')
        descriptions = t('.mode_descriptions')
        IssueRecurrence.modes.map do |k,v|
          mode = "#{intervals[k.to_sym]}(s)"
          mode += ", #{descriptions[k.to_sym]}" unless descriptions[k.to_sym].empty?
          [sanitize(mode, tags:{}), k]
        end
      end

      def anchor_mode_options
        IssueRecurrence.anchor_modes.map do |k,v|
          [sanitize(t(".anchor_modes.#{k}"), tags:{}), k]
        end
      end

      def anchor_to_start_options
        options = [true, false].map do |v|
          [sanitize(t(".anchor_to_start.#{v}"), tags:{}), v]
        end
        disabled = []
        disabled << :true if @issue.start_date.blank? && @issue.due_date.present?
        disabled << :false if @issue.start_date.present? && @issue.due_date.blank?
        [options, disabled]
      end

      def delay_mode_options
        translations = t('.delay_modes')
        IssueRecurrence.delay_modes.map do |k,v|
          [translations[k.to_sym], k]
        end
      end

      def limit_mode_options
        translations = t('.limit_modes')
        options_for_select(translations.map { |k,v| [sanitize(v, tags:{}), k] })
      end

      def last_recurrence(r, intro=true)
        s = intro ? "#{t '.last_recurrence'} " : ""
        if r.last_issue.present?
          s += "#{link_to("##{r.last_issue.id}", issue_path(r.last_issue))}"
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

