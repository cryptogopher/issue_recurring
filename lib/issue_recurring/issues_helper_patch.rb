module IssueRecurring
  module IssuesHelperPatch
    TRANSLATION_ROOT = 'issues.recurrences.form'

    def nameless_error_messages_for(*objects)
      objects = objects.map {|o| o.is_a?(String) ? instance_variable_get("@#{o}") : o}
      errors = objects.compact.map {|o| o.errors.messages.values()}.flatten
      render_error_messages(errors)
    end

    def creation_mode_options
      translations = t("#{TRANSLATION_ROOT}.creation_modes")
      IssueRecurrence.creation_modes.map do |k,v|
        [strip_tags(translations[k.to_sym]), k.to_sym]
      end
    end

    def include_subtasks_options
      [true, false].map do |v|
        [strip_tags(t("#{TRANSLATION_ROOT}.include_subtasks.#{v}")), v]
      end
    end

    def mode_options
      intervals = t("#{TRANSLATION_ROOT}.mode_intervals")
      descriptions = t("#{TRANSLATION_ROOT}.mode_descriptions")
      IssueRecurrence.modes.map do |k,v|
        mode = "#{intervals[k.to_sym]}(s)"
        mode += ", #{descriptions[k.to_sym]}" unless descriptions[k.to_sym].empty?
        [strip_tags(mode), k.to_sym]
      end
    end

    def anchor_mode_options
      IssueRecurrence.anchor_modes.map do |k,v|
        [strip_tags(t("#{TRANSLATION_ROOT}.anchor_modes.#{k}")), k.to_sym]
      end
    end

    def anchor_to_start_options
      [true, false].map do |v|
        [strip_tags(t("#{TRANSLATION_ROOT}.anchor_to_start.#{v}")), v]
      end
    end

    def anchor_to_start_disabled
      disabled = []
      disabled << :true if @issue.start_date.blank? && @issue.due_date.present?
      disabled << :false if @issue.start_date.present? && @issue.due_date.blank?
    end

    def delay_mode_options
      translations = t("#{TRANSLATION_ROOT}.delay_modes")
      IssueRecurrence.delay_modes.map do |k,v|
        [strip_tags(translations[k.to_sym]), k.to_sym]
      end
    end

    def limit_mode_options
      t("#{TRANSLATION_ROOT}.limit_modes").map { |k,v| [strip_tags(v), k] }
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

    def format_dates(dates_list)
      dates_str = dates_list.map { |dates| "#{dates[:start]} - #{dates[:due]}" }.join(", ")
      dates_str.empty? ? '-' : dates_str
    end

    def next_recurrences(dates_list, intro=true)
      "#{"#{t '.next_recurrence'} " if intro}#{format_dates(dates_list)}".html_safe
    end

    def predicted_recurrences(dates_list, intro=true)
      "#{"#{t '.predicted_recurrence'} " if intro}#{format_dates(dates_list)}".html_safe
    end

    def delete_button(r)
      link_to l(:button_delete), recurrence_path(r), method: :delete, remote: true,
        class: 'icon icon-del' if r.editable?
    end
  end
end
