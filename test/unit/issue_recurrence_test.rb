require_relative '../test_helper'

class IssueRecurrenceTest < ActiveSupport::TestCase
  self.fixture_path = File.expand_path('../../fixtures/', __FILE__)
  fixtures :issues, :issue_statuses,
    :users, :email_addresses, :trackers, :projects,
    :roles, :members, :member_roles, :enabled_modules, :workflow_transitions,
    :custom_fields, :enumerations

  def setup
    @issue1 = issues(:issue_01)
    @issue2 = issues(:issue_02)
    @issue3 = issues(:issue_03)

    User.current = users(:alice)
  end

  def test_new
    @issue1.update!(start_date: '2019-04-08', due_date: '2019-04-12')
    ir = IssueRecurrence.new(issue: @issue1)
    assert ir
    ir.save!
  end

  def test_copy_issue_relations_removes_unselected_types
    recurrence = IssueRecurrence.new(issue: @issue1)
    stray = IssueRelation.create!(issue_from: @issue2, issue_to: @issue3,
                                  relation_type: 'blocks')

    recurrence.send(:copy_issue_relations, @issue1, @issue2, [])

    assert_not IssueRelation.exists?(stray.id)
  ensure
    stray.destroy if stray&.persisted?
  end

  def test_copy_issue_relations_removes_unselected_incoming_types
    recurrence = IssueRecurrence.new(issue: @issue1)
    stray = IssueRelation.create!(issue_from: @issue3, issue_to: @issue2,
                                  relation_type: 'blocks')

    recurrence.send(:copy_issue_relations, @issue1, @issue2, [])

    assert_not IssueRelation.exists?(stray.id)
  ensure
    stray.destroy if stray&.persisted?
  end

  def test_copy_issue_relations_skips_duplicate_relations
    recurrence = IssueRecurrence.new(issue: @issue1)
    source = IssueRelation.create!(issue_from: @issue1, issue_to: @issue3,
                                   relation_type: 'relates')
    duplicate = IssueRelation.create!(issue_from: @issue2, issue_to: @issue3,
                                      relation_type: 'relates')

    assert_no_difference 'IssueRelation.count' do
      recurrence.send(:copy_issue_relations, @issue1, @issue2, ['relates'])
    end
    assert_equal '', recurrence.journal_notes
  ensure
    source.destroy if source&.persisted?
    duplicate.destroy if duplicate&.persisted?
  end

  def test_copy_issue_relations_copies_only_selected_outgoing_type
    recurrence = IssueRecurrence.new(issue: @issue1)
    source = IssueRelation.create!(issue_from: @issue1, issue_to: @issue3,
                                   relation_type: 'blocks')

    recurrence.send(:copy_issue_relations, @issue1, @issue2, ['blocks'])

    copied = IssueRelation.find_by(issue_from: @issue2, issue_to: @issue3,
                                   relation_type: 'blocks')
    assert copied
    assert_equal 1, IssueRelation.where(issue_from: @issue2, issue_to: @issue3,
                                        relation_type: 'blocks').count
  ensure
    source.destroy if source&.persisted?
    copied&.destroy if copied&.persisted?
  end

  def test_copy_issue_relations_copies_only_selected_incoming_type
    recurrence = IssueRecurrence.new(issue: @issue1)
    source = IssueRelation.create!(issue_from: @issue3, issue_to: @issue1,
                                   relation_type: 'blocks')

    recurrence.send(:copy_issue_relations, @issue1, @issue2, ['blocked'])

    copied = IssueRelation.find_by(issue_from: @issue3, issue_to: @issue2,
                                   relation_type: 'blocks')
    assert copied
    assert_equal 1, IssueRelation.where(issue_from: @issue3, issue_to: @issue2,
                                        relation_type: 'blocks').count
  ensure
    source.destroy if source&.persisted?
    copied&.destroy if copied&.persisted?
  end

  def test_copy_issue_relations_skips_unselected_outgoing_type
    recurrence = IssueRecurrence.new(issue: @issue1)
    source = IssueRelation.create!(issue_from: @issue1, issue_to: @issue3,
                                   relation_type: 'blocks')

    recurrence.send(:copy_issue_relations, @issue1, @issue2, ['blocked'])

    refute IssueRelation.exists?(issue_from: @issue2, issue_to: @issue3,
                                 relation_type: 'blocks')
  ensure
    source.destroy if source&.persisted?
  end

  def test_copy_issue_relations_skips_unselected_incoming_type
    recurrence = IssueRecurrence.new(issue: @issue1)
    source = IssueRelation.create!(issue_from: @issue3, issue_to: @issue1,
                                   relation_type: 'blocks')

    recurrence.send(:copy_issue_relations, @issue1, @issue2, ['blocks'])

    refute IssueRelation.exists?(issue_from: @issue3, issue_to: @issue2,
                                 relation_type: 'blocks')
  ensure
    source.destroy if source&.persisted?
  end
end
