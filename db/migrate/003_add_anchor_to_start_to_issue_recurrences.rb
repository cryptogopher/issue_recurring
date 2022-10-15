class AddAnchorToStartToIssueRecurrences < ActiveRecord::Migration[4.2]
  @@old_modes = {
    monthly_start_day_from_first: 200,
    monthly_due_day_from_first: 201,
    monthly_start_day_to_last: 210,
    monthly_due_day_to_last: 211,
    monthly_start_dow_from_first: 220,
    monthly_due_dow_from_first: 221,
    monthly_start_dow_to_last: 230,
    monthly_due_dow_to_last: 231,
    monthly_start_wday_from_first: 240,
    monthly_due_wday_from_first: 241,
    monthly_start_wday_to_last: 250,
    monthly_due_wday_to_last: 251
  }

  @@new_modes = {
    monthly_day_from_first: 202,
    monthly_day_to_last: 212,
    monthly_dow_from_first: 222,
    monthly_dow_to_last: 232,
    monthly_wday_from_first: 242,
    monthly_wday_to_last: 252
  }

  @@mode_conversion = {
    @@old_modes[:monthly_start_day_from_first] =>
      {mode: @@new_modes[:monthly_day_from_first], anchor_to_start: true},
    @@old_modes[:monthly_due_day_from_first] =>
      {mode: @@new_modes[:monthly_day_from_first], anchor_to_start: false},

    @@old_modes[:monthly_start_day_to_last] =>
      {mode: @@new_modes[:monthly_day_to_last], anchor_to_start: true},
    @@old_modes[:monthly_due_day_to_last] =>
      {mode: @@new_modes[:monthly_day_to_last], anchor_to_start: false},

    @@old_modes[:monthly_start_dow_from_first] =>
      {mode: @@new_modes[:monthly_dow_from_first], anchor_to_start: true},
    @@old_modes[:monthly_due_dow_from_first] =>
      {mode: @@new_modes[:monthly_dow_from_first], anchor_to_start: false},

    @@old_modes[:monthly_start_dow_to_last] =>
      {mode: @@new_modes[:monthly_dow_to_last], anchor_to_start: true},
    @@old_modes[:monthly_due_dow_to_last] =>
      {mode: @@new_modes[:monthly_dow_to_last], anchor_to_start: false},

    @@old_modes[:monthly_start_wday_from_first] =>
      {mode: @@new_modes[:monthly_wday_from_first], anchor_to_start: true},
    @@old_modes[:monthly_due_wday_from_first] =>
      {mode: @@new_modes[:monthly_wday_from_first], anchor_to_start: false},

    @@old_modes[:monthly_start_wday_to_last] =>
      {mode: @@new_modes[:monthly_wday_to_last], anchor_to_start: true},
    @@old_modes[:monthly_due_wday_to_last] =>
      {mode: @@new_modes[:monthly_wday_to_last], anchor_to_start: false},
  }

  class IssueRecurrence < ActiveRecord::Base
  end

  def up
    add_column :issue_recurrences, :anchor_to_start, :boolean
    IssueRecurrence.reset_column_information

    IssueRecurrence.all.each do |ir|
      # Should operate on values as stored in db (and not things like enum
      # names declared in ActiveRecord::IssueRecurrence, as that may change in
      # future and invalidate this migration).
      attrs = ir.attributes
      if @@mode_conversion.has_key?(attrs["mode"])
        ir.update!(@@mode_conversion[attrs["mode"]])
      else
        ref_issue_id = attrs["last_issue_id"] if attrs["anchor_mode"].between?(1, 3)
        ref_issue_id ||= attrs["issue_id"]
        ref_issue = Issue.find(ref_issue_id)
        ir.update_attribute(:anchor_to_start,
                            ref_issue.start_date.present? && ref_issue.due_date.blank?)
      end
    end
  end

  def down
    mode_reversion = @@mode_conversion.invert
    IssueRecurrence.all.each do |ir|
      attrs = ir.attributes
      reversion_key = {mode: attrs["mode"], anchor_to_start: attrs["anchor_to_start"]}
      if mode_reversion.has_key?(reversion_key)
        ir.update_attribute(:mode, mode_reversion[reversion_key])
      end
    end

    remove_column :issue_recurrences, :anchor_to_start
  end
end
