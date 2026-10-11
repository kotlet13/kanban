/// Inbox receipts expire after seven elapsed days, independently of the age
/// or completion state of the task/payment that generated the notification.
const inboxReadRetention = Duration(days: 7);

bool inboxReadExpired(DateTime? readAt, DateTime now) =>
    readAt != null &&
    !readAt.toUtc().add(inboxReadRetention).isAfter(now.toUtc());
