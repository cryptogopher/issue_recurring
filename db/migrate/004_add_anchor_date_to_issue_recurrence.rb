class AddAnchorDateToIssueRecurrence <
  (Rails::VERSION::MAJOR < 5 ? ActiveRecord::Migration : ActiveRecord::Migration[4.2])

  def change
    add_column :issue_recurrences, :anchor_date, :date
  end
end
