from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


from api_server import extract_event_from_preview, parse_stats_line
from llm_client import DEFAULTS, _parse_timeout


def test_parse_stats_line_valid():
    line = "Processed: 12 | Created events: 3 | Not created: 8 | Failed: 1"
    assert parse_stats_line(line) == {
        "processed": 12,
        "created": 3,
        "not_created": 8,
        "failed": 1,
    }


def test_parse_stats_line_invalid_fallback():
    assert parse_stats_line("nothing useful") == {
        "processed": 0,
        "created": 0,
        "not_created": 0,
        "failed": 0,
    }


def test_extract_event_from_preview_direct_range():
    item = {
        "subject": "Planning Meeting",
        "summary": "Review milestones",
        "event_preview": "2026-05-01 10:00:00-2026-05-01 11:00:00 @ Room A",
    }
    event = extract_event_from_preview(item)
    assert event is not None
    assert event["title"] == "Planning Meeting"
    assert event["start_datetime"] == "2026-05-01 10:00:00"
    assert event["end_datetime"] == "2026-05-01 11:00:00"
    assert event["location"] == "Room A"


def test_parse_timeout_variants():
    assert _parse_timeout("5, 42") == (5.0, 42.0)
    assert _parse_timeout([1, 2]) == (1.0, 2.0)
    assert _parse_timeout("bad") == DEFAULTS["timeout"]
