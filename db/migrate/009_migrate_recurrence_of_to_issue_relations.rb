class MigrateRecurrenceOfToIssueRelations < ActiveRecord::Migration[4.2]
  class User < ActiveRecord::Base; end
  class Issue < ActiveRecord::Base; end
  class IssueRelation < ActiveRecord::Base; end
  class Journal < ActiveRecord::Base; end
  class JournalDetail < ActiveRecord::Base; end

  def relation_journal(from_id, to_id, user_id, relation, reverse, direction)
    [
      {
        entry: {journalized_id: from_id,
                journalized_type: 'Issue', user_id: user_id, notes: ''},
        detail: {property: 'relation', prop_key: relation,
                 old_value: direction ? nil : to_id.to_s,
                 value: direction ? to_id.to_s : nil}
      },
      {
        entry: {journalized_id: to_id,
                journalized_type: 'Issue', user_id: user_id, notes: ''},
        detail: {property: 'relation', prop_key: reverse,
                 old_value: direction ? nil : from_id.to_s,
                 value: direction ? from_id.to_s : nil}
      }
    ]
  end

  def up
    creates = []
    updates = {}
    journals = []

    # To distinguish relations created by migration from those of normal
    # recurrence renewal, set admin as journals author
    admin_id = User.where(admin: true).pluck(:id).min

    say('Processing issue relations...')
    issues = Issue.arel_table
    issue_relations = IssueRelation.arel_table
    exec_query(issues
      .where(issues[:recurrence_of_id].not_eq(nil)
             .and(issues[:id].not_eq(issues[:recurrence_of_id])))
      .outer_join(issue_relations)
      .on(issue_relations[:issue_from_id].eq(issues[:recurrence_of_id])
          .and(issue_relations[:issue_to_id].eq(issues[:id])))
      .project(issues[:id], issues[:recurrence_of_id],
               issue_relations[:id].as('relation_id'),
               issue_relations[:relation_type].as('relation_type')).to_sql)
      .each do |item|

        case item['relation_type']
        when "copied_to"
          updates[item['relation_id']] = {relation_type: 'recurs_in'}

          # Nullification of copied_from/copied_to relation
          journals += relation_journal(item['recurrence_of_id'], item['id'], admin_id,
                                       'copied_to', 'copied_from', false)
          # Creation of recurs_in/recurence_of relation
          journals += relation_journal(item['recurrence_of_id'], item['id'], admin_id,
                                       'recurs_in', 'recurrence_of', true)
        when nil
          creates << {issue_from_id: item['recurrence_of_id'], issue_to_id: item['id'],
                      relation_type: 'recurs_in'}
          journals += relation_journal(item['recurrence_of_id'], item['id'], admin_id,
                                       'recurs_in', 'recurrence_of', true)
        else
          # Do nothing as there is already some other kind of relation that
          # should be not intrfered with.
        end
    end

    say("updating #{updates.length} relations", true)
    IssueRelation.update(updates.keys, updates.values)
    say("creating #{creates.length} relations", true)
    IssueRelation.create(creates)
    journals.each do |j|
      j[:detail][:journal_id] = Journal.create(j[:entry]).id
      JournalDetail.create(j[:detail])
    end

    # Reset :recurrence_of, so it no longer points to Issues
    Issue.update_all(recurrence_of_id: nil)
    # Set :recurrence_of for Issues marked as :last_issue (except for :reopens),
    # as we know IssueRecurrence they belong to
    issue_recurrences = IssueRecurrence.arel_table
    update Arel::UpdateManager.new.table(
      Arel::Nodes::JoinSource.new(
        issue_recurrences,
        [
          issue_recurrences.create_join(
            issues,
            issue_recurrences.create_on(
              issue_recurrences[:last_issue_id].eq(issues[:id])
              .and(issue_recurrences[:issue_id].not_eq(issues[:id]))
            )
          )
        ]
      )
    ).set(issues[:recurrence_of_id] => issue_recurrences[:id]).to_sql

    # Remove :last_issue column, value will be obtained from association from now on
    remove_reference :issue_recurrences, :last_issue
  end

  def down
    # Rolling back this migration is limited and cannot guarantee getting
    # pre-migration state of database. The reasons for this are following:
    # 1. on migration, relations between Issues are modified:
    #   a) when there is 'copied' relation, it is replaced with 'recurrence of' relation
    #   b) when there is no relation, the 'recurrence of' relation is created
    #   c) when there is other relation, nothing is changed to not interfere
    #  On rollback, recurrence_of attribute will be restored based on
    #  existence of 'recurrence of' relation. This will restore attribute
    #  properly in cases a) and b), but not on c). Relations in case:
    #   a) will be restored to 'copied' - properly
    #   b) will be restored to 'copied' as there is no way to determine if there
    #   was relation before migration - adds previously nonexistent data
    #   c) nothing will be changed - properly
    #  Any change in these relations post migration will make rollback
    #  unrealiable even more.
    #
    # Regarding in-place recurrences, which cannot have relations, migration
    # will only clear recurrence_of attribute if set (i.e. after first renewal).
    # On rollback, restoration thus needs to be based on recurrence count, so proper
    # state will be restored only when there was no recurrence renewal post
    # migration.
    #
    # Unless there is some worthy case for implementing it, rollback will be
    # unavailable for now.
    raise ActiveRecord::IrreversibleMigration,
      "Migration cannot be reverted properly. See migration source for details"
  end
end
