class IssueRecurrence < ActiveRecord::Base
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
end
