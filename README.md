# issue_recurring

Redmine plugin: schedule Redmine issue recurrence based on multiple conditions.

Issue tracker: https://it.michalczyk.pro/ (don't be afraid, you can register/login there with your __Github account__).

Screenshots: https://it.michalczyk.pro/projects/issue-recurring/wiki/Screenshots

## Motivation

This plugin has been inspired and based on [nutso's](https://github.com/nutso/) plugin [redmine-plugin-recurring-tasks](https://github.com/nutso/redmine-plugin-recurring-tasks). Thank you __nutso__! The code though was rewritten from scratch. It was due to amount of changes would make it impossible to fit into original codebase.

## Purpose

Plugin for Redmine to configure issue recurring according to a schedule. The plugin creates a new issue in Redmine for each new recurrence.

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
* creation of next issue recurrence as a copy of: first issue, last recurrence or without copying, by in-place modification,
* next recurrence scheduling based on: original issue dates, last recurrence dates, close date of last recurrence, last recurrence dates if close on time or close date otherwise,
* ability to specify recurrence based on start or due date of issue (in cases where that matters),
* updating both start and due dates according to schedule (if specified),
* ability to recur with or without subtasks,
* ability to delay recurrence against base date to create multiple recurrences of the same frequency with different time offset (e.g. monthly recurrence on 10th, 20th and 30th day of month),
* ability to limit recurrence by final date or recurrence count,
* showing dates of last/next recurrence and history of recurrences,
* logging errors when renewing issue recurrences as a note (no logging into user-inaccessible log file),
* permissions to view/edit recurrences managed by Redmine roles,
* per project enabling of issue recurring plugin,
* specification of user account under which issue recurrences will be created: any Redmine user or last recurrence author,
* specification of recurrence assignment: can be kept as previous recurrence assignee or set to Redmine default,

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
   * (optional) create separate Redmine user as an author of issue recurrences (Administration -> Users -> New user)
   * grant issue recurring permissions to roles (Administration -> Roles and permissions -> Permissions report). Issue recurring permissions are inside _Issue recurring_ group. There are 2 types of permissions:
     * _View issue recurrences_ - should be granted to everybody who needs to view recurrence information
     * _Manage issue recurrences_ - should be granted for roles responsible for creating/deleting issue recurrences

6. Update plugin settings. (Administration -> Plugins -> Issue recurring plugin -> Configure)

7. Add cron task to enable recurrence creation at least once a day.
   ```
   12 6 * * * cd /var/lib/redmine && RAILS_ENV=production rake redmine:issue_recurring:renew_all >> log/cron-issue_recurring.log
   ```

8. Go to Redmine, create/open issue, add issue recurrence.

9. Have fun!
