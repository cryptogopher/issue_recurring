# Changelog

## 1.7 [????-??-??]

New features:
* Redmine versions supported: 4.2 and 5.0 (#28, #34)
* obsolete Redmine versions: 3.4, 4.0
* more than one future recurrence for fixed schedules can be created by setting
  renew ahead period (#27)
* Bulgarian translation, thanks to @jwalkerbg

Improvements:
* when previous assignee is no longer assignable (e.g. due to account being
  blocked or any other reason recognized by Redmine) and ```keep_assignee``` setting
  is used, default Redmine assignment applies and warning is recorded in
  issue's note (#26)
* when author of new recurrence is given in settings and user does not exist
  (e.g. he because was deleted in the meantime), author is set to that of
  reference issue and warning is recorded in issue's note
* it is now possible to specify Anonymous user as the author of new
  recurrences in plugin settings
 
Fixes:
* formatting of warning messages in journal
* migrations no longer depend on model, which caused some of them to
  fail on upgrade (#35)

## 1.6 [2020-04-11]

* upgraded wording of anchor modes in recurrence form
* added new value for option specifying whether to add journal for new recurrence; now journal can not only be enabled/diabled, but also enabled selectively for _in-place_ recurrences; if you use this option, you can eliminate email notifications on (less important) journal updates on reference issues with _copy_ recurrences, while still getting notifications on: a) new issues created from _copy_ recurrences and b) journal updates on issues with _in-place_ recurrences (#24)
* issue recurrence schemes are now copied along with issue, regardless of whether you copy individual issues or projects; this behavior can be controlled by plugin setting (#21); if recurrence copy fails on project copy (e.g. because issue recurring module is not enabled for project) it is silently ignored; if recurrence copy fails on issue (e.g. because required issue date has been removed) - issue copy is aborted and error reported

## 1.5 [2019-11-29]

* properly handling parent attribute of recurred issue
* reporting in-place recurrence without subtasks as invalid if issue dates are derived from children (previously it was possible to create such recurrence, though it wouldn't recur properly)

## 1.4 [2019-08-19]

* added Spanish translation, thanks to [lupa18](https://github.com/lupa18/)!
* introduced order independent recurrence scheduling when there is more than 1 recurrence schedule assigned to issue; this is rare configuration and situations where order does really matter are even more rare (e.g. when there is non-inplace and inplace schedule or when there are multiple inplace schedules)
* fixed display of _Next_ recurrence dates; _Next_ dates show what recurrences will be created if the renewal process is executed _now_
* added display of _Predicted_ recurrence dates; _Predicted_ dates show what recurrences will be created in future given that no issue dates will change and assuming that non-closed issues will be closed today; this is to give you overview how your schedule(s) work(s) and in future may be extended to show more than 1 future date at a time

## 1.3 [2019-07-14]

* added 2 new scheduling algorithms:
   * based on last recurrence dates, but recurs only after last recurrence has been closed (i.e. after its close date)
   * based on fixed date configured separately from issue's own start/due dates; recurs only after last recurrence close date; this is the only recurrence scheme that allows multiple in-place recurrence schemes for one issue (and has been introduced exactly to allow that)
* changed input form for recurrence creation:
   * recurrence limit input has been changed from radio buttons to drop-down list; it makes form more compact/consistent
   * wording and order of some options has been changed to create (hopefully) more natural reading experience
   * for readability inactive form inputs now fade out and hide instead of being visible but disabled
 
## 1.2 [2019-07-03]

* plugin is now compatible with Redmine 4.0/Rails 5.2, (2019-07-14: well, actually it is compatible with Redmine 4.0, but due to mistake migrations don't work with Redmine 3.4; either update to v1.3 or copy migration files from there)
* it is now disallowed to create multiple in-place recurrence schedules for single issue. No real world scenario could justify such configuration and it might cause problems for the unwary (2020-01-17: this has actually changed in v1.3 and there is new scheduling algorithm introduced to allow multiple in-place recurrences)

## 1.1 [2019-05-04]

* from now on it is possible to explicitly specify if recurrence will be based on start or due date, for every recurrence type. Previously it was only possible for monthly recurrences. All other recurrences were treated automatically, depending on start/due date availability. You can use this feature to e.g. decide how recurrences based on close date will be treated: you can have either start or due date of next recurrence based on close date of the previous one. Upon upgrading all existing recurrences will be migrated according to previous rules, which were as follows:
   * for monthly recurrences things will be kept unchanged (monthly recurrences already had distinct start/due options)
   * for all of the rest: if start date is available and due date is empty for reference issue - recurrence will be based on start date; otherwise recurrence will be based on due date (that is also true for recurrences based on close date, which may have both start and due dates missing; such recurrence will be based on due date as well)
