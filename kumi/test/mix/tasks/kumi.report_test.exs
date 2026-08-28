defmodule Mix.Tasks.Kumi.ReportTest do
  # Runs the REAL `mix kumi.report` task as a real subprocess against the
  # kumi package itself (not a fake/stub of any step) — see
  # test/kumi/report_test.exs for the pure verdict-derivation unit tests.
  #
  # Always passes `--skip-tests`: without it, this step would shell out to
  # `mix test`, which re-runs the WHOLE suite — including this very test —
  # recursively (see Mix.Tasks.Kumi.Report's moduledoc and the v0.4
  # friction log entry on this).
  #
  # The `plan` step is expected to fail here — NOT a bug in kumi.report:
  # `Kumi.Test.Repo` is test/support-only, started manually by
  # test/test_helper.exs, and is not part of the `:kumi` OTP application's
  # own supervision tree, so `Mix.Task.run("app.start")` in a fresh
  # subprocess never starts it (`mix kumi.plan` has this exact same
  # limitation run standalone against the kumi package — this is about
  # kumi's own test fixtures not being a host app, not about kumi.report).
  use ExUnit.Case, async: false

  test "mix kumi.report --skip-tests --json runs the real chain against the kumi package" do
    {output, exit_code} =
      System.cmd("mix", ["kumi.report", "--skip-tests", "--json"],
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      )

    report = Jason.decode!(output)

    assert Enum.map(report["steps"], & &1["name"]) == [
             "format",
             "compile",
             "test",
             "codegen",
             "plan"
           ]

    by_name = Map.new(report["steps"], &{&1["name"], &1})

    assert by_name["compile"]["status"] == "pass"
    assert by_name["test"]["status"] == "skipped"
    assert by_name["test"]["detail"] == "skipped (by flag)"
    assert by_name["codegen"]["status"] == "pass"
    assert by_name["format"]["status"] == "pass"
    assert by_name["plan"]["status"] == "fail"
    assert by_name["plan"]["detail"] =~ "could not build plan"

    assert report["plan"] == nil
    assert report["verdict"] == "failed"
    assert exit_code == 1
  end

  describe "truncate/1" do
    # String.split("", "\n") returns [""], never [] — a failing step with
    # truly empty captured output used to fall through to the `<= 20`
    # branch and print an empty string as `detail` instead of the intended
    # "(no output)" placeholder.
    test "empty output produces the (no output) placeholder" do
      assert Mix.Tasks.Kumi.Report.truncate("") == "(no output)"
    end

    test "whitespace-only output (post ANSI-strip) also counts as no output" do
      assert Mix.Tasks.Kumi.Report.truncate("   \n  \n") == "(no output)"
    end

    test "non-empty output under the line cap passes through unchanged" do
      assert Mix.Tasks.Kumi.Report.truncate("line one\nline two") == "line one\nline two"
    end
  end
end
