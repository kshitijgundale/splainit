## ADDED Requirements

### Requirement: Store successful explanations locally
When history is enabled, the system SHALL store successful explanations in a local app-owned database. Each record SHALL include timestamp, source app name and bundle ID, capture method, selected text, exact context sent if any, preset ID and prompt text, model ID, and reply. The database SHALL not contain the user's API key.

#### Scenario: Successful explanation
- **WHEN** a current invocation receives a reply and history is enabled
- **THEN** one local history record is created with the actual request and reply details

#### Scenario: Failed request
- **WHEN** capture or the LLM request fails
- **THEN** no successful explanation record is created

### Requirement: Browse and search history
The system SHALL allow the user to view past explanations in reverse chronological order and search across selected text, source app, preset, and reply.

#### Scenario: Search past explanation
- **WHEN** the user searches for a term present in a saved selection or reply
- **THEN** matching local records are shown with source and timestamp

### Requirement: Delete stored history
The system SHALL allow deletion of one entry and clearing of all entries without requiring an online account.

#### Scenario: Delete one entry
- **WHEN** the user deletes a history entry
- **THEN** that entry no longer appears in history or search

#### Scenario: Clear all history
- **WHEN** the user clears history
- **THEN** all saved explanation records are removed from the local database

### Requirement: Allow history to be disabled
The system SHALL expose a history setting. Disabling it SHALL stop new explanation records from being written and SHALL leave existing records available for separate deletion.

#### Scenario: History is disabled
- **WHEN** the user receives an explanation while history is disabled
- **THEN** the reply appears in the panel but no new history record is stored

### Requirement: Preserve history across direct updates
The update process SHALL retain the app-owned SQLite history database and existing records when installing a valid signed update from a previous Splainit version. Any schema change SHALL use a forward migration that preserves records, and rollback procedures SHALL account for schema compatibility.

#### Scenario: Previous version is upgraded
- **WHEN** a previous Splainit version with saved explanations is upgraded using a valid Tauri-signed update
- **THEN** the updated app can browse and search the existing local records without data loss
