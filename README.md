# issue_recurring

Redmine plugin: schedule Redmine issue recurrence based on multiple conditions.

Issue tracker: https://ir.michalczyk.pro/ (don't be afraid, you can register/login there with your __Github account__).

Screenshots: https://ir.michalczyk.pro/projects/issue-recurring/wiki/Screenshots

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
  * months with dates keeping the same weekday (according to non-working week days specified in Redmine settings) from the beginning or to the end of the month (e.g. 2nd working day of month or 1st to last working day of month),
  * years,
* creation of next issue recurrence as a copy of: first issue, last recurrence or without copying, by in-place modification,
* next recurrence scheduling based on: original issue dates, last recurrence dates, close date of last recurrence, last recurrence dates if close on time or close date otherwise,
* ability to specify recurrence based on start or due date of issue (in cases where that matters),
* updating both start and due dates according to schedule (if specified),
* ability to recur with or without subtasks,
* ability to delay recurrence against base date to create multiple recurrences of the same frequency with different time offset (e.g. monthly recurrence on 10th, 20th and 30th day of month),
* ability to limit recurrence by final date or recurrence count,
* showing dates of last/next recurrence and history of recurrences,
* logging errors with renewing issue recurrence as an issue note (besides logging into log file inaccessible for user),
* permissions to view/edit recurrences managed by Redmine roles,
* per project enabling of issue recurring plugin,
* specification of user account under which issue recurrences will be created: any Redmine user or last recurrence author,
* specification of recurrence assignment: can be kept as previous recurrence assignee or set to Redmine default,

