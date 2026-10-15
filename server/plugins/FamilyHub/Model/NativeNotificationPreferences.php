<?php
namespace Kanboard\Plugin\FamilyHub\Model;

/** Shared defaults for preference reads, event creation and delivery rechecks. */
class NativeNotificationPreferences extends NativeDatabase
{
    const CATEGORIES = ['tasks', 'events', 'shopping', 'finance', 'reminders', 'membership','ideas'];

    public static function resolve($saved = null)
    {
        $defaults = ['inApp' => true, 'sound' => true, 'push' => true, 'email' => false];
        return $saved === null ? $defaults : array_replace($defaults, json_decode($saved, true, 32, JSON_THROW_ON_ERROR));
    }

    public function settings($scope, $account, $category)
    {
        $row = $this->one('SELECT settings FROM familyhub_inbox_preferences WHERE scope_id=? AND account_id=? AND category=?', [$scope, $account, $category]);
        return self::resolve($row['settings'] ?? null);
    }
}
