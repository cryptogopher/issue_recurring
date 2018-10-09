module IssueRecurrencesHelper
  def issue_link(r)
    link_to "##{r.issue.id}: #{r.issue.subject}", issue_path(r.issue)
  end

  def mode(r)
    s = 'issues.recurrences.form.mode_intervals'
    "#{r.multiplier} #{l("#{s}.#{r.mode}").pluralize(r.multiplier)}"
  end

  def creation_mode(r)
    r.creation_mode.to_s.tr('_', ' ')
  end

  def anchor_mode(r)
    s = 'issues.recurrences.form.delay_intervals'
    t = case r.anchor_mode.to_sym
    when :first_issue_fixed
      "first issue"
    when :last_issue_fixed
      "last issue"
    when :last_issue_flexible
      "last issue close"
    when :last_issue_flexible_on_delay
      "last issue close if delayed"
    end
    t += r.delay_multiplier > 0 ? " + #{r.delay_multiplier}" \
      " #{l("#{s}.#{r.delay_mode}").pluralize(r.delay_multiplier)}" : ''
    t
  end

  def limit_condition(r)
    return "-" if r.date_limit.nil? && r.count_limit.nil?
    return "date: #{r.date_limit}" if r.date_limit.present?
    return "count: #{r.count_limit}" if r.count_limit.present?
  end
end
