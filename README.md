# issue_recurring

Redmine plugin: schedule Redmine issue recurrence based on multiple conditions.

Issue tracker: https://it.michalczyk.pro/ (don't be afraid, you can register/login there with your __Github account__).

Screenshots: https://it.michalczyk.pro/projects/issue-recurring/wiki/Screenshots

## Motivation

This plugin has been inspired and based on [nutso's](https://github.com/nutso/) plugin [redmine-plugin-recurring-tasks](https://github.com/nutso/redmine-plugin-recurring-tasks). Thank you __nutso__! The code though was rewritten from scratch. It was due to amount of changes would make it impossible to fit into original codebase.

## Purpose

Plugin for Redmine to configure issue recurring according to a schedule. The plugin creates a new issue in Redmine for each new recurrence. Because some boring things have to be done on-time after all.

## Features

The most notable features of this plugin include:
* recurrence creation/deletion directly from form on issue page (no separate page, no page reloading when creating/deleting recurrences),
* multiple recurrence schedules per issue possible,
* specification of recurrence frequency by means of:
  * days,
  * working days (according to non-working week days specified in Redmine settings),
  * weeks,
  * months with dates keeping fixed distance from the beginning or to the end of the month (e.g. 2nd to last day of month),
  * months with dates keeping the same day of week from the beginning or to the end of the month (e.g. 2nd Tuesday of month or 1st to last Friday of month),
  * months with dates keeping the same working day (according to non-working week days specified in Redmine settings) from the beginning or to the end of the month (e.g. 2nd working day of month or 1st to last working day of month),
  * years,
* creation of next issue recurrence as a copy of: first issue; last recurrence; without copying, by in-place modification,
* next recurrence scheduling based on: original issue dates; last recurrence dates; close date of last recurrence; last recurrence dates if closed on time or close date otherwise,
* ability to specify recurrence based on start or due date; for recurrence based on close date: ability to specify which of these dates is inferred from close date,
* updating both start and due dates according to schedule (if specified),
* ability to recur with or without subtasks,
* ability to delay recurrence against base date to create multiple recurrences of the same frequency with different time offset (e.g. monthly recurrence on 10th, 20th and 30th day of month),
* ability to limit recurrence by final date or recurrence count,
* showing dates of last/next recurrence and history of recurrences,
* logging errors as an issue note when unable to renew issue recurrences (instead of logging into web-inaccessible log file),
* permissions to view/manage recurrences managed by Redmine roles,
* per project enabling of issue recurring plugin,
* specification of user account under which issue recurrences will be created: any Redmine user or last recurrence author,
* specification of recurrence issue assignment: assignee can be kept unchanged from previous recurrence or set to Redmine's default.

## Changelog

### 1.1

* from now on it is possible to explicitly specify if recurrence will be based on start or due date, for every recurrence type. Previously it was only possible for monthly recurrences. All other recurrences were treated automatically, depending on start/due date availability. You can use this feature to e.g. decide how recurrences based on close date will be treated: you can have either start of due date of next recurrence based on close date of the previous one. Upon upgrading all existing recurrences will be migrated according to previous rules, which were as follows:
   * for monthly recurrences things will be kept unchanged,
   * for all of the rest: if due date is available for issue - recurrence will be based on due date regardless if start date is defined as well; otherwise recurrence will be based on start date (that is true also for recurrences based on close date, which may have both start and due dates missing; such recurrence will be based on start date).

## Installation

1. Check prerequisites. To use this plugin you need to have:
   * Redmine (https://www.redmine.org) installed. Check that your Redmine version is compatible with plugin. Currently supported are following versions of software:

     |        |versions |
     |--------|---------|
     |Redmine |3.x      |
     
     You may try and find this plugin working on other versions too, but be prepared to get error messages. In case it works let everyone know that through issue tracker (send _support_ issue). If it doesn't work, you are welcome to send _feature_ request to make plugin compatible with other version. Keep in mind though, that for more exotic versions there will be more vote power needed to complete such feature request.

2. Login to shell, change to redmine user, clone plugin to your plugins directory, install gemfiles and migrate database:
   ```
   su - redmine
   git -C /var/lib/redmine/plugins/ clone https://github.com/cryptogopher/issue_recurring.git
   cd /var/lib/redmine
   bundle install
   RAILS_ENV=production rake redmine:plugins:migrate
   ```

3. Restart Redmine. Exact steps depend on your installation of Redmine. You may need to restart Apache (when using Passenger) or just Redmine daemon/service.

4. Update Redmine settings.
   * enable _Issue recurring_ module per project (choose project -> Settings -> Modules -> check Issue recurring)
   * (optional) create separate Redmine user as an author of issue recurrences (Administration -> Users -> New user)
   * grant issue recurring permissions to roles (Administration -> Roles and permissions -> Permissions report). Issue recurring permissions are inside _Issue recurring_ group. There are 2 types of permissions:
     * _View issue recurrences_ - should be granted to everybody who needs to view recurrence information
     * _Manage issue recurrences_ - should be granted for roles responsible for creating/deleting issue recurrences

5. Update plugin settings. (Administration -> Plugins -> Issue recurring plugin -> Configure)

6. Add cron task to enable recurrence creation at least once a day.
   ```
   12 6 * * * cd /var/lib/redmine && RAILS_ENV=production rake redmine:issue_recurring:renew_all >> log/cron-issue_recurring.log
   ```

7. Go to Redmine, create/open issue, add issue recurrence.

8. Have fun!

## Upgrade

Will be here shortly!
