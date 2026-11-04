"""test_raw_cfs_echo.py:

Closed-loop integration tests for the raw cFS inter-application echo demonstration.

Two native cFS applications (raw_commander, raw_commanded) exchange raw cFS command and
telemetry packets with two F Prime components (EchoResponder, EchoCommander) over the
software bus. The traffic is periodic (every 10 seconds), so these tests observe the
F Prime events and counting telemetry channels rather than commanding anything.
"""

import time

from fprime_gds.common.utils.event_severity import EventSeverity

RESPONDER = "FPrimeApp.echoResponder"
COMMANDER = "FPrimeApp.echoCommander"
# One raw command per 10 s (raw_commander) and per 10 rate-group ticks (EchoCommander)
PERIOD_S = 10
TIMEOUT_S = 2 * PERIOD_S + 5


def test_responder_receives_raw_command(fprime_test_api):
    """EchoResponder receives raw_commander's cFS command and echoes it as cFS telemetry"""
    fprime_test_api.assert_event(f"{RESPONDER}.CommandReceived", timeout=TIMEOUT_S)
    fprime_test_api.assert_event(f"{RESPONDER}.EchoSent", timeout=TIMEOUT_S)


def test_commander_matches_raw_echo(fprime_test_api):
    """EchoCommander sends a raw cFS command and raw_commanded's telemetry echo matches it"""
    fprime_test_api.assert_event(f"{COMMANDER}.CommandSent", timeout=TIMEOUT_S)
    fprime_test_api.assert_event(f"{COMMANDER}.EchoMatched", timeout=TIMEOUT_S)


def test_echo_counters_increment(fprime_test_api):
    """Every echo event is mirrored by an occurrence counter that keeps increasing"""
    for channel in (f"{RESPONDER}.EchoesSent", f"{COMMANDER}.EchoesMatched"):
        first = fprime_test_api.await_telemetry(channel, timeout=TIMEOUT_S)
        assert first is not None, f"No {channel} telemetry received"
        fprime_test_api.clear_histories()
        later = fprime_test_api.await_telemetry(channel, timeout=TIMEOUT_S)
        assert later is not None, f"No further {channel} telemetry received"
        assert later.get_val() > first.get_val(), f"{channel} did not increase"


def test_no_echo_warnings(fprime_test_api):
    """Nominal traffic raises no warning events from either echo component"""
    fprime_test_api.clear_histories()
    time.sleep(TIMEOUT_S)
    warnings = [
        event
        for event in fprime_test_api.get_event_test_history().retrieve()
        if event.template.get_full_name().startswith((RESPONDER, COMMANDER))
        and event.get_severity() in (EventSeverity.WARNING_LO, EventSeverity.WARNING_HI)
    ]
    assert not warnings, f"Unexpected echo warnings: {[str(w) for w in warnings]}"
    assert fprime_test_api.await_telemetry(f"{COMMANDER}.EchoMismatches", timeout=TIMEOUT_S).get_val() == 0
    assert fprime_test_api.await_telemetry(f"{COMMANDER}.EchoTimeouts", timeout=TIMEOUT_S).get_val() == 0
