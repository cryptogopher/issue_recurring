class AddRecurrenceOfToIssues < ActiveRecord::Migration
  def change
    add_reference :issues, :recurrence_of, index: true
  end
end
