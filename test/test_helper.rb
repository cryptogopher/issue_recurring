# Load the Redmine helper
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')

ActiveRecord::FixtureSet.create_fixtures(
  File.dirname(__FILE__) + '/fixtures/',
  [
    :issues,
    :issue_statuses,
    :issue_priorities,
    :users,
    :email_addresses,
    :trackers,
    :projects,
    :roles,
    :members,
    :member_roles,
    :enabled_modules,
    :workflow_transitions
  ]
)

def logout_user
  post signout_path
end

def create_recurrence(issue=issues(:issue_01), **attributes)
  attributes[:mode] ||= :weekly
  attributes[:multiplier] ||= 1
  assert_difference 'IssueRecurrence.count', 1 do
    post "#{issue_recurrences_path(issue)}.js", params: {recurrence: attributes}
    assert_response :ok
    assert_empty assigns(:recurrence).errors.messages
  end
end

def renew_all(count=0)
  assert_difference 'Issue.count', count do
    IssueRecurrence.renew_all
  end
  count > 0 ? Issue.last(count) : nil
end

def close_issue(issue)
  status = IssueStatus.all.where(is_closed: true).first
  put "/issues/#{issue.id}", params: {issue: {status_id: status.id}}
  issue.reload
  assert_equal issue.status_id, status.id
end

