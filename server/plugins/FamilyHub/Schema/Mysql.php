<?php

namespace Kanboard\Plugin\FamilyHub\Schema;

use PDO;

const VERSION = 13;

function version_1(PDO $pdo)
{
    $pdo->exec('CREATE TABLE familyhub_project_invitations (
        id VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
        project_id INT NOT NULL,
        creator_id INT NOT NULL,
        recipient_id INT NOT NULL,
        request_id VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
        token_hash VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
        created_at BIGINT NOT NULL,
        expires_at BIGINT NOT NULL,
        accepted_at BIGINT DEFAULT NULL,
        revoked_at BIGINT DEFAULT NULL,
        PRIMARY KEY (id),
        UNIQUE KEY familyhub_invitation_token (token_hash),
        UNIQUE KEY familyhub_invitation_request (creator_id, request_id),
        KEY familyhub_invitation_project (project_id),
        FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
        FOREIGN KEY (creator_id) REFERENCES users(id) ON DELETE CASCADE,
        FOREIGN KEY (recipient_id) REFERENCES users(id) ON DELETE CASCADE
    ) ENGINE=InnoDB CHARSET=utf8mb4');
}

function version_2(PDO $pdo)
{
    NativeSchema::create($pdo, true);
}

function version_3(PDO $pdo)
{
    NativeSchema::ensureIdentities($pdo, true);
}

function version_4(PDO $pdo)
{
    CollaborationSchema::create($pdo, true);
}

function version_5(PDO $pdo)
{
    CollaborationSchema::ensureInboxState($pdo, true);
}

function version_6(PDO $pdo)
{
    CollaborationSchema::createDelivery($pdo, true);
}

function version_7(PDO $pdo)
{
    CollaborationSchema::ensureChannels($pdo, true);
}

function version_8(PDO $pdo)
{
    PushSchema::create($pdo,true);
}

function version_9(PDO $pdo)
{
    AccountSchema::create($pdo,true);
}

function version_10(PDO $pdo)
{
    AccountDeletionSchema::create($pdo,true);
}

function version_11(PDO $pdo)
{
    OrganizationSchema::create($pdo, true);
}

function version_12(PDO $pdo)
{
    SpacesSchema::create($pdo, true);
}

function version_13(PDO $pdo)
{
    LinkedPaymentsSchema::create($pdo, true);
}
