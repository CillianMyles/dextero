BEGIN;

--
-- Class Conversation as table spike_conversation
--
CREATE TABLE "spike_conversation" (
    "id" INTEGER PRIMARY KEY,
    "publicId" TEXT NOT NULL,
    "nextSequence" INTEGER NOT NULL
) STRICT;

-- Indexes
CREATE UNIQUE INDEX "spike_conversation_public_id" ON "spike_conversation" ("publicId");


--
-- Class Message as table spike_message
--
CREATE TABLE "spike_message" (
    "id" INTEGER PRIMARY KEY,
    "conversationId" INTEGER NOT NULL,
    "sequence" INTEGER NOT NULL,
    "content" TEXT NOT NULL,
    "source" TEXT NOT NULL DEFAULT ('user'),
    CONSTRAINT "spike_message_fk_0" FOREIGN KEY ("conversationId") REFERENCES "spike_conversation" ("id") ON DELETE NO ACTION ON UPDATE NO ACTION
) STRICT;

-- Indexes
CREATE UNIQUE INDEX "spike_message_sequence" ON "spike_message" ("conversationId", "sequence");


--
-- Class CloudStorageEntry as table serverpod_cloud_storage
--
CREATE TABLE "serverpod_cloud_storage" (
    "id" INTEGER PRIMARY KEY,
    "storageId" TEXT NOT NULL,
    "path" TEXT NOT NULL,
    "addedTime" INTEGER NOT NULL,
    "expiration" INTEGER,
    "byteData" BLOB NOT NULL,
    "verified" INTEGER NOT NULL,
    "contentType" TEXT,
    "cacheControl" TEXT,
    "contentDisposition" TEXT,
    "contentEncoding" TEXT,
    "customMetadata" TEXT
) STRICT;

-- Indexes
CREATE UNIQUE INDEX "serverpod_cloud_storage_path_idx" ON "serverpod_cloud_storage" ("storageId", "path");
CREATE INDEX "serverpod_cloud_storage_expiration" ON "serverpod_cloud_storage" ("expiration");


--
-- Class CloudStorageDirectDownloadEntry as table serverpod_cloud_storage_direct_download
--
CREATE TABLE "serverpod_cloud_storage_direct_download" (
    "id" INTEGER PRIMARY KEY,
    "storageId" TEXT NOT NULL,
    "path" TEXT NOT NULL,
    "expiration" INTEGER NOT NULL,
    "authKey" TEXT NOT NULL,
    "downloadFileName" TEXT,
    "contentType" TEXT
) STRICT;

-- Indexes
CREATE UNIQUE INDEX "serverpod_cloud_storage_direct_download_auth_key" ON "serverpod_cloud_storage_direct_download" ("authKey");
CREATE INDEX "serverpod_cloud_storage_direct_download_expiration" ON "serverpod_cloud_storage_direct_download" ("expiration");


--
-- Class CloudStorageDirectUploadEntry as table serverpod_cloud_storage_direct_upload
--
CREATE TABLE "serverpod_cloud_storage_direct_upload" (
    "id" INTEGER PRIMARY KEY,
    "storageId" TEXT NOT NULL,
    "path" TEXT NOT NULL,
    "expiration" INTEGER NOT NULL,
    "authKey" TEXT NOT NULL,
    "maxFileSize" INTEGER NOT NULL DEFAULT (10485760),
    "contentLength" INTEGER,
    "preventOverwrite" INTEGER NOT NULL DEFAULT (0),
    "contentType" TEXT,
    "cacheControl" TEXT,
    "contentDisposition" TEXT,
    "contentEncoding" TEXT,
    "customMetadata" TEXT
) STRICT;

-- Indexes
CREATE UNIQUE INDEX "serverpod_cloud_storage_direct_upload_storage_path" ON "serverpod_cloud_storage_direct_upload" ("storageId", "path");


--
-- Class FutureCallEntry as table serverpod_future_call
--
CREATE TABLE "serverpod_future_call" (
    "id" INTEGER PRIMARY KEY,
    "name" TEXT NOT NULL,
    "time" INTEGER NOT NULL,
    "serializedObject" TEXT,
    "serverId" TEXT NOT NULL,
    "identifier" TEXT,
    "scheduling" TEXT
) STRICT;

-- Indexes
CREATE INDEX "serverpod_future_call_time_idx" ON "serverpod_future_call" ("time");
CREATE INDEX "serverpod_future_call_serverId_idx" ON "serverpod_future_call" ("serverId");
CREATE INDEX "serverpod_future_call_identifier_idx" ON "serverpod_future_call" ("identifier");


--
-- Class FutureCallClaimEntry as table serverpod_future_call_claim
--
CREATE TABLE "serverpod_future_call_claim" (
    "id" INTEGER PRIMARY KEY,
    "futureCallId" INTEGER,
    "lastHeartbeatTime" INTEGER NOT NULL,
    CONSTRAINT "serverpod_future_call_claim_fk_0" FOREIGN KEY ("futureCallId") REFERENCES "serverpod_future_call" ("id") ON DELETE CASCADE ON UPDATE NO ACTION
) STRICT;

-- Indexes
CREATE UNIQUE INDEX "future_call_unique_idx" ON "serverpod_future_call_claim" ("futureCallId");


--
-- Class ServerHealthConnectionInfo as table serverpod_health_connection_info
--
CREATE TABLE "serverpod_health_connection_info" (
    "id" INTEGER PRIMARY KEY,
    "serverId" TEXT NOT NULL,
    "timestamp" INTEGER NOT NULL,
    "active" INTEGER NOT NULL,
    "closing" INTEGER NOT NULL,
    "idle" INTEGER NOT NULL,
    "granularity" INTEGER NOT NULL
) STRICT;

-- Indexes
CREATE UNIQUE INDEX "serverpod_health_connection_info_timestamp_idx" ON "serverpod_health_connection_info" ("timestamp", "serverId", "granularity");


--
-- Class ServerHealthMetric as table serverpod_health_metric
--
CREATE TABLE "serverpod_health_metric" (
    "id" INTEGER PRIMARY KEY,
    "name" TEXT NOT NULL,
    "serverId" TEXT NOT NULL,
    "timestamp" INTEGER NOT NULL,
    "isHealthy" INTEGER NOT NULL,
    "value" REAL NOT NULL,
    "granularity" INTEGER NOT NULL
) STRICT;

-- Indexes
CREATE UNIQUE INDEX "serverpod_health_metric_timestamp_idx" ON "serverpod_health_metric" ("timestamp", "serverId", "name", "granularity");


--
-- Class LogEntry as table serverpod_log
--
CREATE TABLE "serverpod_log" (
    "id" INTEGER PRIMARY KEY,
    "sessionLogId" INTEGER NOT NULL,
    "messageId" INTEGER,
    "reference" TEXT,
    "serverId" TEXT NOT NULL,
    "time" INTEGER NOT NULL,
    "logLevel" INTEGER NOT NULL,
    "message" TEXT NOT NULL,
    "error" TEXT,
    "stackTrace" TEXT,
    "order" INTEGER NOT NULL,
    CONSTRAINT "serverpod_log_fk_0" FOREIGN KEY ("sessionLogId") REFERENCES "serverpod_session_log" ("id") ON DELETE CASCADE ON UPDATE NO ACTION
) STRICT;

-- Indexes
CREATE INDEX "serverpod_log_sessionLogId_idx" ON "serverpod_log" ("sessionLogId", "order");


--
-- Class MessageLogEntry as table serverpod_message_log
--
CREATE TABLE "serverpod_message_log" (
    "id" INTEGER PRIMARY KEY,
    "sessionLogId" INTEGER NOT NULL,
    "serverId" TEXT NOT NULL,
    "messageId" INTEGER NOT NULL,
    "endpoint" TEXT NOT NULL,
    "messageName" TEXT NOT NULL,
    "duration" REAL NOT NULL,
    "error" TEXT,
    "stackTrace" TEXT,
    "slow" INTEGER NOT NULL,
    "order" INTEGER NOT NULL,
    CONSTRAINT "serverpod_message_log_fk_0" FOREIGN KEY ("sessionLogId") REFERENCES "serverpod_session_log" ("id") ON DELETE CASCADE ON UPDATE NO ACTION
) STRICT;

-- Indexes
CREATE INDEX "serverpod_message_log_sessionLogId_idx" ON "serverpod_message_log" ("sessionLogId", "order");


--
-- Class MethodInfo as table serverpod_method
--
CREATE TABLE "serverpod_method" (
    "id" INTEGER PRIMARY KEY,
    "endpoint" TEXT NOT NULL,
    "method" TEXT NOT NULL
) STRICT;

-- Indexes
CREATE UNIQUE INDEX "serverpod_method_endpoint_method_idx" ON "serverpod_method" ("endpoint", "method");


--
-- Class DatabaseMigrationVersion as table serverpod_migrations
--
CREATE TABLE "serverpod_migrations" (
    "id" INTEGER PRIMARY KEY,
    "module" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "timestamp" INTEGER
) STRICT;

-- Indexes
CREATE UNIQUE INDEX "serverpod_migrations_ids" ON "serverpod_migrations" ("module");


--
-- Class QueryLogEntry as table serverpod_query_log
--
CREATE TABLE "serverpod_query_log" (
    "id" INTEGER PRIMARY KEY,
    "serverId" TEXT NOT NULL,
    "sessionLogId" INTEGER NOT NULL,
    "messageId" INTEGER,
    "query" TEXT NOT NULL,
    "duration" REAL NOT NULL,
    "numRows" INTEGER,
    "error" TEXT,
    "stackTrace" TEXT,
    "slow" INTEGER NOT NULL,
    "order" INTEGER NOT NULL,
    CONSTRAINT "serverpod_query_log_fk_0" FOREIGN KEY ("sessionLogId") REFERENCES "serverpod_session_log" ("id") ON DELETE CASCADE ON UPDATE NO ACTION
) STRICT;

-- Indexes
CREATE INDEX "serverpod_query_log_sessionLogId_idx" ON "serverpod_query_log" ("sessionLogId", "order");


--
-- Class ReadWriteTestEntry as table serverpod_readwrite_test
--
CREATE TABLE "serverpod_readwrite_test" (
    "id" INTEGER PRIMARY KEY,
    "number" INTEGER NOT NULL
) STRICT;


--
-- Class RuntimeSettings as table serverpod_runtime_settings
--
CREATE TABLE "serverpod_runtime_settings" (
    "id" INTEGER PRIMARY KEY,
    "logSettings" TEXT NOT NULL,
    "logSettingsOverrides" TEXT NOT NULL,
    "logServiceCalls" INTEGER NOT NULL,
    "logMalformedCalls" INTEGER NOT NULL
) STRICT;


--
-- Class SessionLogEntry as table serverpod_session_log
--
CREATE TABLE "serverpod_session_log" (
    "id" INTEGER PRIMARY KEY,
    "serverId" TEXT NOT NULL,
    "time" INTEGER NOT NULL,
    "module" TEXT,
    "endpoint" TEXT,
    "method" TEXT,
    "duration" REAL,
    "numQueries" INTEGER,
    "slow" INTEGER,
    "error" TEXT,
    "stackTrace" TEXT,
    "authenticatedUserId" INTEGER,
    "userId" TEXT,
    "isOpen" INTEGER,
    "touched" INTEGER NOT NULL
) STRICT;

-- Indexes
CREATE INDEX "serverpod_session_log_serverid_idx" ON "serverpod_session_log" ("serverId");
CREATE INDEX "serverpod_session_log_time_idx" ON "serverpod_session_log" ("time");
CREATE INDEX "serverpod_session_log_touched_idx" ON "serverpod_session_log" ("touched");
CREATE INDEX "serverpod_session_log_isopen_idx" ON "serverpod_session_log" ("isOpen");


--
-- STORE COLUMN TYPES FOR MIGRATIONS
--
DROP TABLE IF EXISTS "serverpod_sqlite_schema";

CREATE TABLE "serverpod_sqlite_schema" (
    "table_name" TEXT NOT NULL,
    "column_name" TEXT NOT NULL,
    "column_type" TEXT NOT NULL,
    "column_vector_dimension" INTEGER,
    PRIMARY KEY ("table_name", "column_name")
);

INSERT INTO "serverpod_sqlite_schema" VALUES
    ('serverpod_cloud_storage', 'addedTime', 'timestampWithoutTimeZone', NULL),
    ('serverpod_cloud_storage', 'expiration', 'timestampWithoutTimeZone', NULL),
    ('serverpod_cloud_storage', 'verified', 'boolean', NULL),
    ('serverpod_cloud_storage_direct_download', 'expiration', 'timestampWithoutTimeZone', NULL),
    ('serverpod_cloud_storage_direct_upload', 'expiration', 'timestampWithoutTimeZone', NULL),
    ('serverpod_cloud_storage_direct_upload', 'preventOverwrite', 'boolean', NULL),
    ('serverpod_future_call', 'time', 'timestampWithoutTimeZone', NULL),
    ('serverpod_future_call', 'scheduling', 'json', NULL),
    ('serverpod_future_call_claim', 'lastHeartbeatTime', 'timestampWithoutTimeZone', NULL),
    ('serverpod_health_connection_info', 'timestamp', 'timestampWithoutTimeZone', NULL),
    ('serverpod_health_metric', 'timestamp', 'timestampWithoutTimeZone', NULL),
    ('serverpod_health_metric', 'isHealthy', 'boolean', NULL),
    ('serverpod_log', 'time', 'timestampWithoutTimeZone', NULL),
    ('serverpod_message_log', 'slow', 'boolean', NULL),
    ('serverpod_migrations', 'timestamp', 'timestampWithoutTimeZone', NULL),
    ('serverpod_query_log', 'slow', 'boolean', NULL),
    ('serverpod_runtime_settings', 'logSettings', 'json', NULL),
    ('serverpod_runtime_settings', 'logSettingsOverrides', 'json', NULL),
    ('serverpod_runtime_settings', 'logServiceCalls', 'boolean', NULL),
    ('serverpod_runtime_settings', 'logMalformedCalls', 'boolean', NULL),
    ('serverpod_session_log', 'time', 'timestampWithoutTimeZone', NULL),
    ('serverpod_session_log', 'slow', 'boolean', NULL),
    ('serverpod_session_log', 'isOpen', 'boolean', NULL),
    ('serverpod_session_log', 'touched', 'timestampWithoutTimeZone', NULL);

--
-- MIGRATION VERSION FOR host_storage
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('host_storage', '20260907071539456', (unixepoch('now', 'subsecond') * 1000))
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260907071539456', "timestamp" = (unixepoch('now', 'subsecond') * 1000);

--
-- MIGRATION VERSION FOR serverpod
--
INSERT INTO "serverpod_migrations" ("module", "version", "timestamp")
    VALUES ('serverpod', '20260824182259319', (unixepoch('now', 'subsecond') * 1000))
    ON CONFLICT ("module")
    DO UPDATE SET "version" = '20260824182259319', "timestamp" = (unixepoch('now', 'subsecond') * 1000);


COMMIT;
