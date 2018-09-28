class CreateIssueRecurrences < ActiveRecord::Migration
  def change
    create_table :issue_recurrences do |t|
      t.references :issue, foreign: true, index: true
      t.references :last_issue, foreign: true, index: true
      t.date :last_date
      t.date :start_date
      t.date :due_date
      t.boolean :is_fixed_schedule
      t.integer :creation_mode
      t.integer :mode
      t.integer :mode_multiplier
      t.date :date_limit
      t.integer :count_limit
    end
  end
end
