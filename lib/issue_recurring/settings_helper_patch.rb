module IssueRecurring
  module SettingsHelperPatch
    def authors(default_login)
      default_id = User.find_by(login: default_login).try(:id) || 0
      options = options_for_select({t('.author_unchanged') => 0}, default_id)
      users = User.active + [User.anonymous]
      options << options_from_collection_for_select(users, :id, :name, default_id)
    end

    def journal_mode_options(default)
      modes = IssueRecurrence::JOURNAL_MODES
      options_for_select(modes.map { |jm| [t(".journal_modes.#{jm}"), jm] }, default)
    end

    def ahead_mode_options(default)
      modes = IssueRecurrence::AHEAD_MODES
      options_for_select(
        modes.map { |am| [t("issues.recurrences.form.delay_modes.#{am}"), am] }, default
      )
    end

    def relation_copy_options(selected)
      selected = Array(selected).map(&:to_s)
      types = IssueRelation::TYPES.keys
      types = types.sort_by { |type| l(IssueRelation::TYPES[type][:name]) }
      types.map do |type|
        label = l(IssueRelation::TYPES[type][:name])
        content_tag(:label, class: 'block') do
          safe_join([
            check_box_tag('settings[copy_relation_types][]', type,
                          selected.include?(type),
                          id: "settings_copy_relation_types_#{type}"),
            ' ',
            h(label)
          ])
        end
      end.join.html_safe
    end
  end
end

