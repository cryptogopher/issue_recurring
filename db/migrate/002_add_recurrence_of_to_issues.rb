class AddRecurrenceOfToIssues < ActiveRecord::Migration[4.2]
  def change
    add_reference :issues, :recurrence_of, index: true
  end
end
