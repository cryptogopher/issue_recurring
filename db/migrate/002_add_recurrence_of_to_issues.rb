class AddRecurrenceOfToIssues <
  (Rails::VERSION::MAJOR < 5 ? ActiveRecord::Migration : ActiveRecord::Migration[4.2])

  def change
    add_reference :issues, :recurrence_of, index: true
  end
end
