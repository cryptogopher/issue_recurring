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

  def close_issue!(issue)
    assert !issue.closed?, 'Expected issue to be open'
    close_issue(issue)
  end

  def close_issue_tree(root)
    root.self_and_descendants.reverse_each { |issue| close_issue(issue) }
  end

  def prepare_renew_once(recurrence, &block)
    issue = recurrence.last_issue || recurrence.issue
    if [:first_issue_fixed, :last_issue_fixed].include?(recurrence.anchor_mode.to_sym)
      travel_to(issue.start_date || issue.due_date)
    else
      close_issue_tree(issue)
    end

    yield if block_given?

    return issue
  end
  private :prepare_renew_once

  def renew_once(recurrence, &block)
    prepare_renew_once(recurrence, &block)
    IssueRecurrence.renew_all(true)
    recurrence.reload
  end

  def renew_once!(recurrence, count: nil, &block)
    issue = prepare_renew_once(recurrence, &block)
    open_issues = Issue.open.pluck(:id)

    if count
      # TODO: add new: parameter to assert difference on Issue.count (e.g. to
      # check that there are only reopens by setting new: 0)
      assert_difference ->{ Issue.open.count }, count do
        IssueRecurrence.renew_all(true)
      end
    else
      if recurrence.reopen?
        assert_changes ->{ issue.reload.closed? }, from: true, to: false do
          IssueRecurrence.renew_all(true)
        end
      else
        assert_changes ->{ Issue.count } do
          IssueRecurrence.renew_all(true)
        end
      end
    end

    recurrence.reload

    issues = Issue.open.where.not(id: open_issues).to_a
    assert_equal count, issues.length if count
    issues
  end

  # NOTE: update #renew_all to use Issue.open.count like #renew_once!
  # This will make #close_issue! replaceable with #close_issue, as change of
  # Issue#closed? will be checked here instead of in #close_issue!.
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
  #  * if default parameter is set to non-nil:
  #    * for mandatory attributes: use it, eventually sampling from that parameter;
  #    (currently only :creation_mode and :anchor_mode Array arguments are supported)
  #    * for optional attributes: force mandatory attributes necessary to set
  #    optionals and use them
  #  * if default parameter is set to nil:
  #    * for mandatory attributes: don't set, leaving it at model/UI default,
  #    * for optional attributes: don't set if default exists and is neutral
  #    (e.g. delay == 0), otherwise force mandatory attributes to hide optionals
  #    force mandatory attributes to 
  #  `defaults` are not validated.
  #
  # TODO: return `invalid` value ranges per attribute which, when single
  # attribute set to a value from that range, will result in invalid recurrence -
  # then test if controller + UI disallow such settings (or does not accept/save
  # optional attributes)
  def random_recurrence(issue, **defaults)
    conditions = {
      start_date: issue.start_date,
      due_date: issue.due_date,
      dates_derived: issue.dates_derived?
    }.merge(defaults)

    creation_modes =
      case conditions
      in anchor_mode: :first_issue_fixed | :last_issue_fixed |
          {include_subtasks: false, dates_derived: true}
        IssueRecurrence.creation_modes.symbolize_keys.keys - [:reopen]
      else
        IssueRecurrence.creation_modes.symbolize_keys.keys
      end
    creation_modes &= Array(conditions[:creation_mode]) if conditions
      .has_key?(:creation_mode)
    conditions[:creation_mode] = creation_modes.sample || fail(':creation_mode blank')

    conditions[:include_subtasks] =
      case conditions
      in creation_mode: :reopen, dates_derived: true
        true
      else
        [true, false].sample
      end unless conditions.has_key?(:include_subtasks)

    conditions[:multiplier] ||= rand([1..3, 4..10, 11..100, 101..1000].sample)
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
      in creation_mode: :reopen
        [:last_issue_flexible, :last_issue_flexible_on_delay,
         :last_issue_fixed_after_close, :date_fixed_after_close]
      else
        IssueRecurrence.anchor_modes.symbolize_keys.keys
      end
    anchor_modes &= [
      :last_issue_flexible, :last_issue_flexible_on_delay, :date_fixed_after_close
    ] if conditions in start_date: nil, due_date: nil
    anchor_modes -= [
      :last_issue_flexible, :last_issue_flexible_on_delay
    ] if conditions in {delay_multiplier: Integer} | {delay_mode: Symbol|String}
    case conditions
    in anchor_date: ::Date
      anchor_modes &= [:date_fixed_after_close]
    in anchor_date: nil
      anchor_modes.delete(:date_fixed_after_close)
    else
    end
    anchor_modes &= Array(conditions[:anchor_mode]) if conditions.has_key?(:anchor_mode)
    conditions[:anchor_mode] = anchor_modes.sample || fail(':anchor_mode blank')

    if conditions[:anchor_mode] == :date_fixed_after_close
      conditions[:anchor_date] = conditions.fetch(:anchor_date, random_date)
    end

    unless conditions in anchor_mode: :last_issue_flexible|:last_issue_flexible_on_delay
      conditions[:delay_multiplier] = conditions
        .fetch(:delay_multiplier, rand([0..0, 1..366].sample))
      conditions[:delay_mode] = conditions
        .fetch(:delay_mode, IssueRecurrence.delay_modes.keys.sample.to_sym)
    end

    case rand(1..4)
    when 1
      conditions[:date_limit] = conditions.fetch(:date_limit,
        [conditions[:anchor_date], Date.current].compact.max + random_datespan)
    when 2
      conditions[:count_limit] = conditions
        .fetch(:count_limit, rand([1..3, 4..1000].sample))
    else
      # 50% times do not set the limit
    end unless conditions in {date_limit: ::Date} | {count_limit: Integer}

    # Remove non-attributes and attributes with `nil` defaults
    conditions.except(:start_date, :due_date, :dates_derived).compact
  end

  def random_new(issue, **defaults)
    # TODO:
    # * make sure sets are intersectable
    # * include defaults (merge into sets below rules definitions?; setting in
    # result won't allow to detect mutually exclusive defaults)
    # * randomize dates (date_limit, anchor_date) with random_date/random_datespan
    # * set limits on randomized dates
    # * randomize integers (multiplier/delay_multiplier/count_limit)
    # * allow multiple nils in date/count_limit to set probability of non-nil
    # * try to work on ranges to be able to provide invalid values later; also
    # work on a sets copy
    sets = {
      creation_mode: IssueRecurrence.creation_modes.symbolize_keys.keys,
      include_subtasks: [false, true],
      multiplier: 1..,
      mode: IssueRecurrence.modes.symbolize_keys.keys,
      anchor_to_start: [false, true],
      anchor_mode: IssueRecurrence.anchor_modes.symbolize_keys.keys,
      anchor_date: [nil, Date.new(0)..]
      delay_multiplier: [nil, 0..],
      delay_mode: [nil, **IssueRecurrence.delay_modes.symbolize_keys.keys],
      date_limit: [nil, Date.current..],
      count_limit: [nil, 1..]
    }

    result = {
      start_date: issue.start_date,
      due_date: issue.due_date,
      dates_derived: issue.dates_derived?
    }

    rules = {
      {start_date: ::Date, due_date: nil} => {
        only: {anchor_to_start: [true]}
      },
      {start_date: nil, due_date: ::Date} => {
        only: {anchor_to_start: [false]}
      },
      {start_date: nil, due_date: nil} => {
        only: {anchor_mode: [:last_issue_flexible, :last_issue_flexible_on_delay,
                             :date_fixed_after_close]}
      },

      {dates_derived: true, include_subtasks: false} => {
        except: {creation_mode: [:reopen]}
      },
      {dates_derived: true, creation_mode: :reopen} => {
        only: {include_subtasks: [true]}
      },

      {creation_mode: :reopen} => {
        except: {anchor_mode: [:first_issue_fixed, :last_issue_fixed]}
      },

      {anchor_mode: :first_issue_fixed} => {
        except: {
          creation_mode: [:reopen],
          delay_multiplier: [nil],
          delay_mode: [nil]
        },
        only: {anchor_date: [nil]}
      },
      {anchor_mode: :last_issue_fixed} => {
        except: {
          creation_mode: [:reopen],
          delay_multiplier: [nil],
          delay_mode: [nil]
        },
        only: {anchor_date: [nil]}
      },
      {anchor_mode: :last_issue_flexible} => {
        only: {
          delay_multiplier: [nil],
          delay_mode: [nil],
          anchor_date: [nil]
        }
      },
      {anchor_mode: :last_issue_flexible_on_delay} => {
        only: {
          delay_multiplier: [nil],
          delay_mode: [nil],
          anchor_date: [nil]
        }
      },
      {anchor_mode: :last_issue_fixed_after_close} => {
        except: {
          delay_multiplier: [nil],
          delay_mode: [nil]
        },
        only: {anchor_date: [nil]}
      },
      {anchor_mode: :date_fixed_after_close} => {
        except: {
          delay_multiplier: [nil],
          delay_mode: [nil],
          anchor_date: [nil]
        }
      },

      {anchor_date: ::Date} => {
        only: {anchor_mode: [:date_fixed_after_close]},
        # FIXME: Replacing could add non-nil when only nil allowed
        replace: {date_limit: [nil, ->{ result[:anchor_date].. }]}
      },
      {anchor_date: nil} => {
        except: {anchor_mode: [:date_fixed_after_close]}
      },

      {delay_multiplier: Integer} => {
        except: {anchor_mode: [:last_issue_flexible, :last_issue_flexible_on_delay]}
      },
      {delay_mode: Symbol} => {
        except: {anchor_mode: [:last_issue_flexible :last_issue_flexible_on_delay]}
      },

      {date_limit: ::Date} => {
        only: {count_limit: [nil]}
      },
      {count_limit: Integer} => {
        only: {date_limit: [nil]}
      },
    }

    unless rules.empty? do
      candidates = []
      rules.each do |condition, effect|
        case
        when rules in condition
          # Apply and delete matching rule
          # NOTE: change to subtract?; or divide subsets into
          # :only (intersect)/:except (subtract)/:replace
          effect.each { |attr, subset| sets[attr] &= subset if sets[attr] }
          rules.delete(condition)
        when (condition.keys - result.keys).empty?
          # Delete non-matching rule dependent on already known values
          rules.delete(condition)
        when !(condition.keys & result.keys).empty?
          # NOTE: should work regardless of order
          # Save partially missing attributes for rule as next candidate
          #candidates << condition.keys - result.keys
        end
      end

      # Sample additional attributes to satisfy at least one rule
      #new_attrs = candidates.sample || rules.keys.sample.keys
      new_attrs = rules.keys.sample.keys
      # Everything outside of `sets[attr]` should yield model/UI error
      # Lack of items to choose from signifies too stringent defaults
      new_attrs.each { |attr| result[attr] = sets.delete(attr).sample }
    end

    # Fill attributes for which no rules exist
    sets.each { |attr| result[attr] = sets[attr].empty? ? fail : sets[attr].sample }
    # Remove non-attributes and attributes with `nil` defaults
    result.except(:start_date, :due_date, :dates_derived).compact
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
