class IssueRecurrence < ActiveRecord::Base
  belongs_to :issue
  has_one :last_issue, class_name: 'Issue'

  enum creation_mode: {
    copy_first: 0,
    copy_last: 1,
    in_place: 2
  }

  enum mode: {
    daily: 0,
    weekly: 1,
    monthly_day_from_first: 2,
    monthly_day_to_last: 3,
    monthly_dow_from_first: 4,
    monthly_dow_to_last: 5,
    monthly_wday_from_first: 6,
    monthly_wday_to_last: 7,
    yearly: 8
  }

  validates :issue, presence: true, associated: true
  validates :last_issue, associated: true
  validates :is_fixed_schedule, inclusion: {in: [false, true]}
  validates :creation_mode, inclusion: {in: creation_modes.keys}
  validates :mode, inclusion: {in: modes.keys}
  validates :mode_multiplier, numericality: {greater_than: 0, only_integer: true}
  validates :date_limit, absence: {if: "count_limit.present?"}
  validates :count_limit, absence: {if: "date_limit.present?"}
  validates :count_limit, numericality: {allow_nil: true, only_integer: true}

  after_initialize :set_defaults

  protected

  def set_defaults
    if new_record?
      self.is_fixed_schedule ||= true
      self.creation_mode ||= :copy_first
      self.mode ||= :monthly_day_from_first
      self.mode_multiplier ||= 1
    end
  end
end
