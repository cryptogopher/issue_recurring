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
    s = 'issues.recurrences.form'
    t = "#{l("issue_recurrences.index.anchor_modes.#{r.anchor_mode}")}" \
      " #{strip_tags(l("#{s}.anchor_to_start.#{r.anchor_to_start}"))}"
    t += r.delay_multiplier > 0 ? " + #{r.delay_multiplier}" \
      " #{l("#{s}.delay_intervals.#{r.delay_mode}").pluralize(r.delay_multiplier)}" : ''
    t
  end

  def limit_condition(r)
    return "-" if r.date_limit.nil? && r.count_limit.nil?
    return "date: #{r.date_limit}" if r.date_limit.present?
    return "count: #{r.count_limit}" if r.count_limit.present?
  end
end
