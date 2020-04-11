# Load the Redmine helper
require File.expand_path(File.dirname(__FILE__) + '/../../../test/test_helper')
require File.expand_path('../test_case', __FILE__)

class IssueRecurringIntegrationTestCase < Redmine::IntegrationTest
  fixtures :issues, :issue_statuses,
    :users, :email_addresses, :trackers, :projects,
    :roles, :members, :member_roles, :enabled_modules, :workflow_transitions,
    :custom_fields, :enumerations

  include IssueRecurringTestCase

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

  def set_parent_issue(parent, child)
    parent_id = parent && parent.id
    assert_not_equal [parent_id], [child.parent_issue_id]
    put "/issues/#{child.id}", params: {issue: {parent_issue_id: parent_id}}
    child.reload
    assert_equal [parent_id], [child.parent_issue_id]
  end

  def set_priority(issue, priority)
    assert_not_equal priority.id, issue.priority_id
    put "/issues/#{issue.id}", params: {issue: {priority_id: priority.id}}
    issue.reload
    assert_equal priority.id, issue.priority_id
  end

  def set_done_ratio(issue, ratio)
    put "/issues/#{issue.id}", params: {issue: {done_ratio: ratio}}
    issue.reload
    assert_equal ratio, issue.done_ratio
  end

  def set_custom_field(issue, field, value)
    if Redmine::VERSION::MAJOR >= 4
      assert_nil issue.custom_field_value(field)
    else
      assert_empty issue.custom_field_value(field)
    end
    put "/issues/#{issue.id}", params: {issue: {custom_field_values: {field.id => value}}}
    issue.reload
    assert_equal value, issue.custom_field_value(field)
  end

  def set_time_entry(issue, hours)
    old_hours = issue.spent_hours
    assert_difference 'issue.reload.spent_hours', hours do
      post "/issues/#{issue.id}/time_entries", params: {
        :time_entry => {
          :hours => hours, :activity_id => enumerations(:time_entry_activity_01).id
        }
      }
    end
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

  def update_plugin_settings(**s)
    assert User.current.admin
    settings = Setting.plugin_issue_recurring.merge(s)
    post plugin_settings_path(id: 'issue_recurring'), params: {settings: settings}
    assert_redirected_to plugin_settings_path(id: 'issue_recurring')
  end

  def copy_project(project)
    assert User.current.admin
    assert_difference 'Project.count', 1 do
      post copy_project_path(project), params: {
        project: {
          name: "copy of: #{project.name} at [#{DateTime.current.strftime('%F %R')}]",
          identifier: "#{project.identifier}-#{DateTime.current.strftime('%Y%m%d%H%M%S')}",
          inherit_members: 1,
          enabled_module_names: project.enabled_modules.map(&:name)
        }
      }
    end
    new_project = Project.last
    assert_redirected_to settings_project_path(new_project)
    new_project
  end

  def copy_issue(from_issue, to_project, **attrs)
    assert_difference 'Issue.count', 1 do
      post project_issues_path(to_project), params: {
        copy_from: from_issue.id,
        issue: attrs
      }
    end
    new_issue = Issue.last
    assert_redirected_to issue_path(new_issue)
    new_issue
  end
end
