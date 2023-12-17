module IssueRecurringTestCase
  if ENV['PROFILE']
    RubyProf.start

    Minitest.after_run do
      File.open('tmp/screenshots/profile.out', 'w') do |file|
        result = RubyProf.stop
        #printer = RubyProf::GraphHtmlPrinter.new(result)
        printer = RubyProf::FlatPrinter.new(result)
        #printer.print(STDOUT, min_percent: 0.1)
        printer.print(file)
      end
    end
  end

  def renew_all(count=0)
    assert_difference 'Issue.count', count do
      IssueRecurrence.renew_all(true)
    end
    count == 1 ? Issue.last : Issue.last(count)
  end

  def random_datespan
    rand([0..7, 8..31, 32..3650].sample)
  end

  def random_date
    Date.current + random_datespan * [-1, 1].sample
  end

  def random_dates
    dates = {start_date: random_date}
    dates.update(due_date: dates[:start_date] + random_datespan)
  end

  def random_recurrence
    r = {
      creation_mode: IssueRecurrence.creation_modes.keys.sample.to_sym,
      include_subtasks: [true, false].sample,
      multiplier: rand([1..4, 5..100, 101..1000].sample),
      mode: IssueRecurrence.modes.keys.sample.to_sym,
      anchor_to_start: [true, false].sample
    }

    disallowed = (r[:creation_mode] == :reopen) ? [:first_issue_fixed, :last_issue_fixed] : []
    r[:anchor_mode] = (IssueRecurrence.anchor_modes.keys.map(&:to_sym) - disallowed).sample

    r[:anchor_date] = random_date if r[:anchor_mode] == :date_fixed_after_close

    unless IssueRecurrence::FLEXIBLE_ANCHORS.map(&:to_sym).include? r[:anchor_mode]
      r[:delay_multiplier] = rand([0..0, 1..366].sample)
      r[:delay_mode] = IssueRecurrence.delay_modes.keys.sample.to_sym
    end

    case rand(1..4)
    when 1
      r[:date_limit] = Date.current + rand([1..31, 32..3650].sample).days
    when 2
      r[:count_limit] = rand([0..12, 13..1000].sample)
    else
      # 50% times do not set the limit
    end

    r
  end

  class Date < ::Date
    def self.today
      # Due to its nature, Date.today may sometimes be equal to Date.yesterday/tomorrow.
      # https://rails.lighthouseapp.com/projects/8994-ruby-on-rails/tickets
      # /6410-dateyesterday-datetoday
      # For this reason WE SHOULD NOT USE Date.today anywhere in the code and use
      # Date.current instead.
      raise "Date.today should not be called!"
    end
  end
end
