# README

Plugin for Redmine to schedule Redmine issue recurrence according to a schedule (see __Features__ below for possible scheduling options). Plugin creates new issue or reopens existing issue for each new recurrence. Because some boring things have to be done on-time after all.

[Changelog](https://github.com/cryptogopher/issue_recurring/blob/master/CHANGELOG.md)

[Issue tracker](https://it.michalczyk.pro/projects/issue-recurring/issues) (you can register and login there with your __Github account__).

[Screenshots](https://it.michalczyk.pro/projects/issue-recurring/wiki/Screenshots)

## Motivation

This plugin has been inspired and based on [nutso's](https://github.com/nutso/) plugin [redmine-plugin-recurring-tasks](https://github.com/nutso/redmine-plugin-recurring-tasks). Thank you __nutso__! The code though was rewritten from scratch. It was due to amount of changes would make it impossible to fit into original codebase.

## Features

Greatest emphasis in development is put on reliability. Scheduling algorithms are tested for accuracy. Unusual situations are reported to user in a visible manner during use. Avoiding regressions and eliminating bugs is valued over new functionalities.

The most notable features of this plugin include:
* recurrence creation/deletion directly from form on issue page (no separate page, no page reloading when creating/deleting recurrences),
* multiple recurrence schedules per issue possible (except for in-place recurrences not based on fixed date),
* specification of recurrence frequency by means of:
  * days,
  * working days (according to non-working week days specified in Redmine settings),
  * weeks,
  * months with dates keeping fixed distance from the beginning or to the end of the month (e.g. 2nd to last day of month),
  * months with dates keeping the same day of week from the beginning or to the end of the month (e.g. 2nd Tuesday of month or 1st to last Friday of month),
  * months with dates keeping the same working day (according to non-working week days specified in Redmine settings) from the beginning or to the end of the month (e.g. 2nd working day of month or 1st to last working day of month),
  * years,
* creation of next issue recurrence as a copy of: first issue; last recurrence; without copying, by in-place modification,
* next recurrence scheduling based on: original issue dates; last recurrence dates; close date of last recurrence; last recurrence dates if closed on time or close date otherwise; last recurrence dates but only after it has been closed; fixed date after last recurrence has been closed,
* ability to specify recurrence based on start or due date; for recurrence based on close date: ability to specify which of dates - start or due - is inferred from close date,
* updating both start and due dates according to schedule (if specified),
* properly handling issue attributes, including keeping: parent, custom fields, priority and resetting: done ratio, time entries and status,
* ability to recur with or without subtasks,
* ability to have recurrence schemes copied regardless of whether individual issues or whole projects are copied,
* ability to delay recurrence against base date to create multiple recurrences of the same frequency with different time offset (e.g. monthly recurrence on 10th, 20th and 30th day of month),
* ability to limit recurrence by final date or recurrence count,
* showing last recurrence and dates of next/predicted recurrences,
* logging errors as an issue note, when unable to renew issue recurrences (instead of logging into web-inaccessible log file),
* permissions to view/manage recurrences managed by Redmine roles,
* per project enabling of issue_recurring plugin,
* specification of user account under which issue recurrences will be created: any Redmine user or last recurrence author,
* specification of recurrence issue assignment: assignee can be kept unchanged from previous recurrence or set to Redmine's default.

## Installation

1. Check prerequisites. To use this plugin you need to have [Redmine](https://www.redmine.org) installed. Check that your Redmine version is compatible with plugin. Only [stable Readmine releases](https://redmine.org/projects/redmine/wiki/Download#Stable-releases) are supported by new releases. Currently supported are following versions:

   |Redmine |Compatible plugin versions|Tested with                                                                                                        |
   |--------|--------------------------|-------------------------------------------------------------------------------------------------------------------|
   |5.0     |current                   |Redmine 5.0.2, Ruby 2.7.6p219, Rails 6.1.6                                                                         |
   |4.2     |current                   |Redmine 4.2.7, Ruby 2.7.6p219, Rails 5.2.8                                                                         |
   |4.0     |1.2 - 1.6                 |Redmine 4.0.4, Ruby 2.4.6p354, Rails 5.2.3                                                                         |
   |3.4     |1.0 - 1.6                 |1.5 - 1.6: Redmine 3.4.5, Ruby 2.4.7p357, Rails 4.2.11.1<br/>1.0 - 1.4: Redmine 3.4.5, Ruby 2.3.8p459, Rails 4.2.11|

   You may try and find this plugin working on other versions too. The best is to
   run test suite and if it passes without errors, everything will most
   probably be ok:
   ```
   cd /var/lib/redmine
   RAILS_ENV=test bundle exec rake redmine:plugins:test NAME=issue_recurring
   ```

2. Login to shell, change to redmine user, clone plugin to your plugins directory, list and choose which plugin version to install, install gemfiles and migrate database:
   ```
   su - redmine
   cd /var/lib/redmine/plugins/
   git clone https://github.com/cryptogopher/issue_recurring.git
   
   # Following 2 steps allow you to run particular version of plugin. Generally it is advised to go with the highest
   # available version, as it is most feature rich. But you can omit those 2 commands ang go with latest code as well.
   git -C issue_recurring/ tag
   # Doing checkout this way you will get "You are in 'detached HEAD' state." warning; it's ok to ignore it
   git -C issue_recurring/ checkout tags/1.4
   
   cd /var/lib/redmine
   bundle install
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=issue_recurring
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
   12 6 * * * cd /var/lib/redmine && RAILS_ENV=production bundle exec rake redmine:issue_recurring:renew_all >> log/cron-issue_recurring.log
   ```

7. Go to Redmine, create/open issue, add issue recurrence.

8. Have fun!

## Upgrade

1. Read [Changelog](https://github.com/cryptogopher/issue_recurring/blob/master/CHANGELOG.md) to know what to expect from upgrade. Sometimes upgrade may require additional steps to be taken. Exact information will be given there.

2. Create backup of current plugin installation. Upgrade process should be reversible in case you only do it between released versions (as opposed to upgrading to some particular git commit). But it's better to be safe than sorry, so make a copy of plugin directory and database. It should go like that (but the exact steps can vary depending on your installation, e.g. database backup step is given for MySQL only):
   ```
   cd /var/lib/redmine
   # stop Redmine instance before continuing
   tar czvf /backup/issue_recurring-$(date +%Y%m%d).tar.gz -C plugins/issue_recurring/ .
   mysqldump --host <DB hostname> --user <DB username> -p <DB name> > /backup/issue_recurring-$(date +%Y%m%d).sql
   # start Redmine instance before continuing
   
   ```
   
3. Using redmine user update plugin code to desired version (version number is at the end of ```git checkout``` command) , check gem requirements and migrate database:

   ```
   su - redmine
   cd /var/lib/redmine/plugins/issue_recurring/
   git fetch --prune --prune-tags
   # choose version from this list
   git tag
   # doing checkout this way you can get "You are in 'detached HEAD' state." warning; it's ok to ignore it
   git checkout tags/1.4
   
   cd /var/lib/redmine
   bundle update
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=issue_recurring
   ```

4. Restart Redmine. Exact steps depend on your installation of Redmine.

5. Check for new plugin settings and set if necessary. (Administration -> Plugins -> Issue recurring plugin -> Configure)

## Downgrade

Upgrade steps should work for downgrade also, given that you do them in reverse - except for backup, which should be done first ;) (e.g. backup, downgrade database, then pull older plugin code version).

Database downgrade (```VERSION``` number ```<NNN>``` is a number taken from migration file name in _issue_recurring/db/migrate_):
   ```
   ca /var/lib/redmine
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate VERSION=<NNN> NAME=issue_recurring
   ```
Keep in mind though, that downgrading database might cause some information to be lost irreversibly. This is because some downgrades may require deletion of tables/columns that were introduced in higher version. Also structure of the data may not be compatible between versions, so the automatic conversion can be lossy.
