import pytest

from app.catalog import ExerciseResolver, normalize


class FakeGroup:
    def __init__(self, id, title):
        self.id = id
        self.title = title


class FakeClient:
    """Duck-type del SpeedianceClient para el resolver."""
    def __init__(self, groups, details):
        self._groups = groups
        self._details = details  # group_id -> detalle
        self.detail_calls = 0

    def exercise_groups(self):
        return self._groups

    def exercise_group(self, group_id):
        self.detail_calls += 1
        return self._details[group_id]


def make_client():
    groups = [
        FakeGroup(116, "Barbell Bench Press"),
        FakeGroup(200, "Dual-Handle Zottman Curl"),
        FakeGroup(300, "Standing Dual-Handle Hammer Curl"),
    ]
    details = {
        116: {"isLeftRight": 0, "isBarbell": 1,
              "actionLibraryList": [{"id": 424195710320641, "isDisplay": 1}]},
        200: {"isLeftRight": 1, "isBarbell": 0,
              "actionLibraryList": [{"id": 999001, "isDisplay": 1}]},
        300: {"isLeftRight": 0, "isBarbell": 0,
              "actionLibraryList": [{"id": 999002, "isDisplay": 1}]},
    }
    return FakeClient(groups, details)


def test_normalize_strips_accents_and_case():
    assert normalize("  Bíceps  Curl ") == "biceps curl"
    assert normalize("Barbell Bench Press") == "barbell bench press"


def test_exact_match_resolves(tmp_path):
    resolver = ExerciseResolver(make_client(), cache_path=tmp_path / "c.json")
    resolved, unmatched = resolver.resolve_all(["Barbell Bench Press"])
    assert unmatched == []
    assert resolved["barbell bench press"]["actionLibraryId"] == 424195710320641
    assert resolved["barbell bench press"]["isBarbell"] is True
    assert resolved["barbell bench press"]["isLeftRight"] is False


def test_accent_insensitive_match(tmp_path):
    resolver = ExerciseResolver(make_client(), cache_path=tmp_path / "c.json")
    resolved, unmatched = resolver.resolve_all(["bárbell bench press"])
    assert unmatched == []
    assert "barbell bench press" in resolved


def test_prefix_match(tmp_path):
    resolver = ExerciseResolver(make_client(), cache_path=tmp_path / "c.json")
    resolved, unmatched = resolver.resolve_all(["Dual-Handle Zottman"])
    assert unmatched == []
    assert resolved["dual-handle zottman"]["actionLibraryId"] == 999001
    assert resolved["dual-handle zottman"]["isLeftRight"] is True


def test_fuzzy_match(tmp_path):
    resolver = ExerciseResolver(make_client(), cache_path=tmp_path / "c.json")
    resolved, unmatched = resolver.resolve_all(["Barbell Bench Pres"])  # falta una s
    assert unmatched == []
    assert "barbell bench pres" in resolved


def test_unmatched_name_is_reported(tmp_path):
    resolver = ExerciseResolver(make_client(), cache_path=tmp_path / "c.json")
    resolved, unmatched = resolver.resolve_all(["Encogimiento Quantum 3000"])
    assert resolved == {}
    assert unmatched == ["Encogimiento Quantum 3000"]


def test_cache_avoids_second_detail_call(tmp_path):
    client = make_client()
    cache = tmp_path / "c.json"
    ExerciseResolver(client, cache_path=cache).resolve_all(["Barbell Bench Press"])
    resolver2 = ExerciseResolver(make_client(), cache_path=cache)
    resolved, _ = resolver2.resolve_all(["Barbell Bench Press"])
    assert resolved  # viene del cache
    assert resolver2._client.detail_calls == 0
