# README

Plugin to schedule Redmine issue recurrence (see __Features__ below for possible scheduling options). Plugin creates new issue or reopens existing issue for each recurrence.

[Changelog](https://github.com/cryptogopher/issue_recurring/blob/master/CHANGELOG.md)

[Issue tracker](https://it.michalczyk.pro/projects/issue-recurring/issues) (you can register and login there with your __Github account__).

[Screenshots](https://it.michalczyk.pro/projects/issue-recurring/wiki/Screenshots) (outdated)

## Features

Greatest emphasis in development is put on reliability. Scheduling algorithms are tested for accuracy. Unusual situations are reported to user in a visible manner during use. Avoiding regressions and eliminating bugs is valued over new functionalities.

The most notable features of this plugin include:
* seamless integration with Redmine regarding look and workflow,
* recurrence schedule creation/edition/deletion directly from form on issue page (no page reloading),
* multiple recurrence schedules per issue possible (except for _reopen_ recurrence based on close date, where only 1 schedule is possible),
* creation of next recurrence by means of:
  * copying first issue,
  * copying last recurrence of issue,
  * without copying, by reopening issue
* specification of recurrence frequency by means of:
  * days,
  * working days (according to non-working week days specified in Redmine settings),
  * weeks,
  * months with dates keeping fixed distance from the beginning or to the end of the month (e.g. 2nd to last day of month),
  * months with dates keeping the same day of week from the beginning or to the end of the month (e.g. 2nd Tuesday of month or 1st to last Friday of month),
  * months with dates keeping the same working day (according to non-working week days specified in Redmine settings) from the beginning or to the end of the month (e.g. 2nd working day of month or 1st to last working day of month),
  * years,
* ability to decide whether start or due date is inferred from base date (the other date is calculated to keep datespan of issue unchanged),
* setting next recurrence date based on:
  * original issue date,
  * last recurrence date,
  * close date of last recurrence,
  * last recurrence date if closed on time or close date otherwise,
  * last recurrence date but only after it has been closed,
  * fixed date after last recurrence has been closed
* ability to delay recurrence against base date to create multiple recurrences of the same frequency with different time offset (e.g. monthly recurrence on 10th, 20th and 30th day of month),
* handling recurrence attributes, including keeping _parent_, _custom fields_, _priority_ and resetting _done ratio_, _time entries_ and _status_,
* ability to recur with or without subtasks,
* ability to have recurrence schemes copied regardless of whether individual issues or whole projects are copied,
* ability to limit recurrence schedule by final date or recurrence count,
* ability to create recurrences ahead in the future,
* showing last recurrence and dates of next/predicted recurrences,
* logging errors as an issue note if unable to renew recurrence (instead of logging into web-inaccessible log file),
* permissions to view/manage recurrence schedules managed by Redmine roles,
* per project enabling of plugin,
* specification of recurrence author: selected Redmine user (including Anonymous) or author of previous recurrence,
* specification of recurrence assignment: keep unchanged from previous recurrence or set to Redmine's default.

## Installation

1. Check prerequisites. To use this plugin you need to have [Redmine](https://www.redmine.org) installed. Check that your Redmine version is compatible with plugin. Only [stable Readmine releases](https://redmine.org/projects/redmine/wiki/Download#Stable-releases) are supported by new releases. Currently supported are following versions:

   |Redmine |Compatible plugin versions|Tested with                                                                                                        |
   |--------|--------------------------|-------------------------------------------------------------------------------------------------------------------|
   |5.0     |1.7 -                     |Redmine 5.0.2, Ruby 2.7.6p219, Rails 6.1.6                                                                         |
   |4.2     |1.7 -                     |Redmine 4.2.7, Ruby 2.7.6p219, Rails 5.2.8                                                                         |
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

## Troubleshooting

Problems often arise when there are multiple plugins installed. If you notice issues, please follow steps:

1. Uninstall all plugins except issue_recurring. Check if problem persist. If yes, go to step 3. 

2. Install & remove other plugins one by one, each time trying to reproduce the issue. There can be more than 1 plugin causing issues, so it's best to test one by one to identify all of them. Once you'll find plugin(s) responsible for problems, go to step 3.

3. [Fill bug report](https://it.michalczyk.pro/projects/issue-recurring/issues) sharing your discoveries. You may want to additionally attach:
   * Redmine log file (_log/production.log_), with log level set to :debug if possible,
   * Redmine Info page contents (http(s)://your.redmine.com/admin/info, you need to be logged in as Administrator),
   * command line output - if problem occurs during cron job.

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

## Development

Running tests:
* all, including system tests:

  ```
  cd /var/lib/redmine
  RAILS_ENV=test bundle exec rake redmine:plugins:test NAME=issue_recurring
  ```
* single test, optionally with seed
  ```
  RAILS_ENV=test bundle exec ruby plugins/issue_recurring/test/system/issue_recurrences_test.rb --name test_update_recurrence --seed 63157
  ```
