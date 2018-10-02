class CreateIssueRecurrences < ActiveRecord::Migration
  def change
    create_table :issue_recurrences do |t|
      t.references :issue, foreign: true, index: true
      t.references :last_issue, foreign: true, index: true
      t.integer :count
      t.integer :creation_mode
      t.integer :anchor_mode
      t.integer :mode
      t.integer :multiplier
      t.date :date_limit
      t.integer :count_limit
    end
  end
end
