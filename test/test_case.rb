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

  def renew_once(recurrence, &block)
    issue = recurrence.issue
    close_issue_tree(issue)
    travel_to([issue.due_date || issue.start_date, Date.current].max) unless recurrence.reopen?

    yield if block_given?

    # Make sure at least one renewal took place
    assert_changes -> { recurrence.reopen? ? issue.reload.closed? : Issue.count } do
      IssueRecurrence.renew_all(true)
    end
  end

  # TODO: treat count as all created + reopened issues to simplify testing
  # also: return all reopened and created issues
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

  def random_future_date
    Date.current + random_datespan + 1.day
  end

  def random_dates
    base_date = random_date
    [
      {start_date: nil, due_date: nil},
      {start_date: base_date, due_date: nil},
      {start_date: nil, due_date: base_date},
      {start_date: base_date, due_date: base_date + random_datespan}
    ].sample
  end

  # Create _valid_ random recurrence for `issue`, optionally setting parameters
  # from `defaults` in following way:
  #  * if default parameter is set to non-nil, for mandatory attributes use it
  #    directly, without randomization of that parameter; for optional attributes
  #    use it directly only if attribute is set
  #  * if default parameter is set to nil, don't set it at all (applies only to
  #    optional attributes)
  #  `defaults` are not validated.
  #
  # TODO: return auxiliary information regarding what conditions can be changed and
  # in what way to obtain invalid recurrence - then test if UI disallows such
  # settings
  def random_recurrence(issue, **defaults)
    optional = defaults.extract!(:anchor_date, :delay_multiplier, :delay_mode,
                                 :date_limit, :count_limit)
    optional.default = false
    conditions = {
      start_date: issue.start_date,
      due_date: issue.due_date,
      dates_derived: issue.dates_derived?
    }.merge(defaults)

    conditions[:creation_mode] ||= IssueRecurrence.creation_modes.keys.sample.to_sym

    conditions[:include_subtasks] =
      case conditions
      in creation_mode: :reopen, dates_derived: true
        true
      else
        [true, false].sample
      end unless conditions.has_key?(:include_subtasks)

    conditions[:multiplier] ||= rand([1..4, 5..100, 101..1000].sample)
    conditions[:mode] ||= IssueRecurrence.modes.keys.sample.to_sym

    conditions[:anchor_to_start] =
      case conditions
      in start_date: ::Date, due_date: nil
        true
      in start_date: nil, due_date: ::Date
        false
      else
        [true, false].sample
      end unless conditions.has_key?(:anchor_to_start)

    anchor_modes =
      case conditions
      in start_date: nil, due_date: nil
        [:last_issue_flexible, :last_issue_flexible_on_delay, :date_fixed_after_close]
      in creation_mode: :copy_first | :copy_last
        IssueRecurrence.anchor_modes.keys
      in creation_mode: :reopen
        [:last_issue_flexible, :last_issue_flexible_on_delay,
         :last_issue_fixed_after_close, :date_fixed_after_close]
      end
    anchor_modes.delete(:date_fixed_after_close) if optional[:anchor_date].nil?
    conditions[:anchor_mode] ||= anchor_modes.sample.to_sym

    if conditions[:anchor_mode] == :date_fixed_after_close
      conditions[:anchor_date] = optional.fetch(:anchor_date, random_date)
    end

    if [:last_issue_flexible, :last_issue_flexible_on_delay].exclude? conditions[:anchor_mode]
      conditions[:delay_multiplier] = optional.fetch(:delay_multiplier,
                                                     rand([0..0, 1..366].sample))
      conditions[:delay_mode] = optional.fetch(:delay_mode,
                                               IssueRecurrence.delay_modes.keys.sample.to_sym)
    end

    case rand(1..4)
    when 1
      conditions[:date_limit] = optional.fetch(:date_limit,
        (conditions[:anchor_date] || Date.current) + rand([1..31, 32..3650].sample).days)
    when 2
      conditions[:count_limit] = optional.fetch(:count_limit, rand([0..12, 13..1000].sample))
    else
      # 50% times do not set the limit
    end

    # Remove non-attributes and attributes with `nil` defaults
    conditions.except(:start_date, :due_date, :dates_derived).compact
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
