ActiveRecord::FixtureSet.create_fixtures(
  File.dirname(__FILE__) + '/fixtures/',
  [
    :issues,
    :issue_statuses,
    :users,
    :email_addresses,
    :trackers,
    :projects,
    :roles,
    :members,
    :member_roles,
    :enabled_modules,
    :workflow_transitions,
    :custom_fields,
    :enumerations
  ]
)

