from brain_dump_history import env


def test_env_values_parses_systemd_env_file_format(tmp_path):
    f = tmp_path / "env"
    f.write_text(
        "# comment line\n"
        "BRAIN_DUMP_URL=https://x.supabase.co\n"
        'BRAIN_DUMP_ANON_KEY="anon.abc"\n'
        "EMPTY=\n"
        "BRAIN_DUMP_TOKEN_FILE=~/certs/tok\n"
    )
    values = env.env_values(f)
    assert values["BRAIN_DUMP_URL"] == "https://x.supabase.co"
    assert values["BRAIN_DUMP_ANON_KEY"] == "anon.abc"
    assert values["BRAIN_DUMP_TOKEN_FILE"] == "~/certs/tok"


def test_env_values_skips_blank_and_malformed_lines(tmp_path):
    f = tmp_path / "env"
    f.write_text("unset\n=\n  \nKEY=value\n")
    assert env.env_values(f) == {"KEY": "value"}


def test_env_values_missing_file_returns_empty(tmp_path):
    assert env.env_values(tmp_path / "nope") == {}


def test_get_prefers_process_env_over_env_file(tmp_path, monkeypatch):
    f = tmp_path / "env"
    f.write_text("BRAIN_DUMP_URL=https://file.supabase.co\n")
    values = {"BRAIN_DUMP_URL": "https://process.supabase.co"}
    monkeypatch.setattr("brain_dump_history.env.os.environ", values)
    assert env.get("BRAIN_DUMP_URL", env_file=f) == "https://process.supabase.co"


def test_get_falls_back_to_env_file(tmp_path, monkeypatch):
    f = tmp_path / "env"
    f.write_text("BRAIN_DUMP_URL=https://file.supabase.co\n")
    monkeypatch.setattr("brain_dump_history.env.os.environ", {})
    assert env.get("BRAIN_DUMP_URL", env_file=f) == "https://file.supabase.co"
    assert env.get("BRAIN_DUMP_MISSING", "fallback", env_file=f) == "fallback"
