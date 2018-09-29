require File.expand_path('../../test_helper', __FILE__)

class IssueRecurrenceTest < ActiveSupport::TestCase
  fixtures :issues

  def setup
    @issue1 = issues(:issue_01)
  end

  def test_new
    ir = IssueRecurrence.new(issue: @issue1)
    assert ir
    ir.save!
  end
end
