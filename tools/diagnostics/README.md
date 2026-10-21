# Local synthetic crypto diagnostics

`local_crypto_runner.py` runs one selected Flutter test file using the existing
SDK and resolved dependencies. It does not build/install/launch a phone app,
extract device state, start a server, or retry a failed run. The selected harness
must use synthetic in-memory data and must not contact a live service.

Example for the new production-path diagnostic harness, after source review:

```sh
python3 tools/diagnostics/local_crypto_runner.py \
  --test test/organizer/data/e2ee/crypto_account_choice_diagnostic_harness_test.dart \
  --scenario account-choice-production-path \
  --wall-timeout 180
```

Do not run earlier passing suites or reset the old claim-continuation test's
three-attempt counter through this tool. The example is a new synthetic
production-path reproduction, not a replay of the iPhone's database or proof of
native synchronization. The runner itself cannot prove a selected test avoids
network/device calls; review the harness first.

Each invocation reserves `build/qa/local-diagnostics/<scenario>/attempt-1..3/`
atomically before launch. Compile failures and interrupted runs consume an
attempt. Keep the same scenario slug for the same issue across fixture changes;
never delete or rename these directories to reset the cap. There is no automatic
retry. A fourth invocation refuses to launch. An interrupted process can leave
an incomplete attempt directory, which remains evidence and consumes its slot.

The default whole-process limit is 180 seconds, each Flutter test has a 45-second
limit, and total process output is capped at 2 MiB. Timeout/output overflow stops
only the spawned local process group, with SIGTERM then SIGKILL if necessary.
Limits can be set explicitly within the bounded CLI ranges. No shell command is
constructed from test output.

`manifest.json` records source/runner hashes, SDK hashes, dependency locks and
package configuration hash, command, platform, limits, and environment variable
names. It does not record environment values. Source files are hashed in place;
there is no source tree copy. `result.json` records the outcome, test counts,
escaping test errors, finite diagnostic stages, and sanitized Dart source frames.
Frames retain source URI, line/column, safe symbol and asynchronous gaps. Local
absolute paths become repository-relative; unrelated absolute paths and arbitrary
non-frame text are omitted. Raw stdout/stderr and exception messages are never
written to disk. Output/line caps are explicit failure classifications, not a
claim that the entire error was captured.

Harness events use a fixed prefix inside `print`:

```dart
print('JIVIE_DIAGNOSTIC ${jsonEncode({
  'version': 1,
  'stage': 'current_head_check',
  'outcome': 'failed',
  'errorType': error.runtimeType.toString(),
  'code': 'crypto_account_choices_stale', // exact fixed source code only
  'stack': stack.toString(),
})}');
```

Do not pass `error.toString()`, payloads, signed commands, IDs, URLs, keys, or
credentials. The runner only accepts static stages `setup`, `incoming_verify`,
`owner_receipt`, `owner_replay`, `current_pull`, `current_wire_open`,
`current_head_check`, `journal_immutable`, and `scenario_result`; outcomes are `entered`, `passed`,
or `failed`. Codes must be exact existing fixed source literals; unknown values
become `other`. Unexpected event fields are omitted.

A caught expected failure is labeled `harness_caught_error`. Flutter machine
`error` events are separately labeled `escaping_test_error`. Numeric engine test
IDs associate events with only the four fixed synthetic scenario names; arbitrary
test names are not retained. Each scenario must have its own passed engine test,
`journal_immutable`, and `scenario_result` evidence. The two stale-head scenarios
require their exact expected caught code and source frames, yielding
`REPRODUCED_EXPECTED_FAILURE`; pending delivery yields `PENDING_GUARD_CONFIRMED`;
the matching-head control requires no caught failure and yields
`MATCHING_HEAD_CONTROL_PASS`. Only all four confirmed scenarios yield aggregate
`synthetic_reproduction_and_controls_confirmed`. A name filter that omits cases
leaves the missing cases `UNVERIFIED`. These are synthetic reproduction/control
results and never an app/native PASS. Missing completion, skipped tests, protocol
errors, compilation failure, timeout, output overflow and source changes have
separate non-PASS outcomes. Compiler diagnostics retain safe source locations
and finite categories (`type_mismatch`, `undefined_symbol`, `syntax`, `other`)
without arbitrary source snippets or compiler message text.
