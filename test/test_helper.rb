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
  assert_nil session[:user_id]
end

def create_recurrence(issue=issues(:issue_01), **attributes)
  attributes[:anchor_mode] ||= :first_issue_fixed
  attributes[:mode] ||= :weekly
  attributes[:multiplier] ||= 1
  assert_difference 'IssueRecurrence.count', 1 do
    post "#{issue_recurrences_path(issue)}.js", params: {recurrence: attributes}
    assert_response :ok
    assert_empty assigns(:recurrence).errors
  end
  IssueRecurrence.last
end

def create_recurrence_should_fail(issue=issues(:issue_01), **attributes)
  attributes[:anchor_mode] ||= :first_issue_fixed
  attributes[:mode] ||= :weekly
  attributes[:multiplier] ||= 1
  error_code = attributes.delete(:error_code) || :ok
  assert_no_difference 'IssueRecurrence.count' do
    post "#{issue_recurrences_path(issue)}.js", params: {recurrence: attributes}
    assert_response error_code
  end
  if error_code == :ok
    assert_not_empty assigns(:recurrence).errors
    assigns(:recurrence).errors
  end
end

def destroy_recurrence(recurrence)
  assert_difference 'IssueRecurrence.count', -1 do
    delete "#{recurrence_path(recurrence)}.js"
    assert_response :ok
    assert_empty assigns(:recurrence).errors
  end
end

def destroy_recurrence_should_fail(recurrence, **attributes)
  error_code = attributes.delete(:error_code) || :ok
  assert_no_difference 'IssueRecurrence.count' do
    delete "#{recurrence_path(recurrence)}.js"
    assert_response error_code
  end
  if error_code == :ok
    assert_not_empty assigns(:recurrence).errors
    assigns(:recurrence).errors
  end
end

def renew_all(count=0)
  assert_difference 'Issue.count', count do
    IssueRecurrence.renew_all
  end
  count == 1 ? Issue.last : Issue.last(count)
end

def set_parent_issue(parent, child)
  assert_not_equal child.parent_issue_id, parent.id
  put "/issues/#{child.id}", params: {issue: {parent_issue_id: parent.id}}
  child.reload
  assert_equal child.parent_issue_id, parent.id
end

def reopen_issue(issue)
  assert issue.closed?
  closed_on = issue.closed_on
  status = issue.tracker.default_status
  put "/issues/#{issue.id}", params: {issue: {status_id: status.id}}
  issue.reload
  assert_equal status.id, issue.status_id
  assert_equal closed_on, issue.closed_on
  assert !issue.closed?
end

def close_issue(issue)
  assert !issue.closed?
  closed_on = issue.closed_on
  status = IssueStatus.all.where(is_closed: true).first
  put "/issues/#{issue.id}", params: {issue: {status_id: status.id}}
  issue.reload
  assert_equal status.id, issue.status_id
  assert_not_nil issue.closed_on
  assert issue.closed?
end

def destroy_issue(issue)
  project = issue.project
  assert_not issue.reload.destroyed?
  assert_difference 'Issue.count', -1 do
    delete issue_path(issue)
    assert_redirected_to project_issues_path(project)
  end
  assert_raises(ActiveRecord::RecordNotFound) { issue.reload }
end
