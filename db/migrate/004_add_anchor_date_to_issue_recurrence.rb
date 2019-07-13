class AddAnchorDateToIssueRecurrence < ActiveRecord::Migration[4.2]
  def change
    add_column :issue_recurrences, :anchor_date, :date
  end
end
