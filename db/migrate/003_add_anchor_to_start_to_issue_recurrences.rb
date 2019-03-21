class AddAnchorToStartToIssueRecurrences < ActiveRecord::Migration
  def change
    add_column :issue_recurrences, :anchor_to_start, :boolean
  end
end
