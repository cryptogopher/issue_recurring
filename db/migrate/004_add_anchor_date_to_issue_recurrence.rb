class AddAnchorDateToIssueRecurrence < ActiveRecord::Migration
  def change
    add_column :issue_recurrences, :anchor_date, :date
  end
end
