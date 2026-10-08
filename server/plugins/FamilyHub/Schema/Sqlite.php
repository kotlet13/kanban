<?php

namespace Kanboard\Plugin\FamilyHub\Schema;

use PDO;

const VERSION = 11;

function version_1(PDO $pdo)
{
    $pdo->exec('CREATE TABLE familyhub_project_invitations (
        id VARCHAR(32) PRIMARY KEY,
        project_id INTEGER NOT NULL REFERENCES projects(id) ON DELETE CASCADE,
        creator_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        recipient_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        request_id VARCHAR(64) NOT NULL,
        token_hash VARCHAR(64) NOT NULL UNIQUE,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        accepted_at INTEGER DEFAULT NULL,
        revoked_at INTEGER DEFAULT NULL,
        UNIQUE (creator_id, request_id)
    )');
    $pdo->exec('CREATE INDEX familyhub_invitation_project ON familyhub_project_invitations(project_id)');
}

function version_2(PDO $pdo)
{
    NativeSchema::create($pdo, false);
}

function version_3(PDO $pdo)
{
    NativeSchema::ensureIdentities($pdo, false);
}

function version_4(PDO $pdo)
{
    CollaborationSchema::create($pdo, false);
}

function version_5(PDO $pdo)
{
    CollaborationSchema::ensureInboxState($pdo, false);
}

function version_6(PDO $pdo)
{
    CollaborationSchema::createDelivery($pdo, false);
}

function version_7(PDO $pdo)
{
    CollaborationSchema::ensureChannels($pdo, false);
}

function version_8(PDO $pdo)
{
    PushSchema::create($pdo,false);
}

function version_9(PDO $pdo)
{
    AccountSchema::create($pdo,false);
}

function version_10(PDO $pdo)
{
    AccountDeletionSchema::create($pdo,false);
}

function version_11(PDO $pdo)
{
    OrganizationSchema::create($pdo, false);
}
