defmodule Mix.Tasks.Kumi.Report do
  @moduledoc """
  The verification harness of the AI patch pipeline (blueprint §8): an AI
  agent (external to Kumi — Kumi never embeds one) patches source; this
  task then runs the full validation chain and emits a machine-readable
  verdict for "is this ready for PR?".

      mix kumi.report               # human-readable checklist
      mix kumi.report --json        # machine-readable JSON on stdout (see
                                     # `Kumi.Report.Json`'s moduledoc for
                                     # the schema)
      mix kumi.report --skip-tests  # skip the `mix test` step (the caller
                                     # manages tests separately)
      mix kumi.report --strict      # exit 0 only for verdict "ready"
                                     # (default: "ready_with_migration"
                                     # also exits 0)
      mix kumi.report --app MyApp.App  # scope the plan step to one app,
                                     # same as `mix kumi.plan --app`

  ## Steps (always run in this order, each reported individually)

    1. `format`  — `mix format --check-formatted`
    2. `compile` — `mix compile --warnings-as-errors`
    3. `test`    — `mix test` (skipped by `--skip-tests`)
    4. `codegen` — `mix ash.codegen --check` (does AshPostgres consider
                    migrations up to date? — see `mix help ash.codegen`)
    5. `plan`    — `Kumi.plan`/`Kumi.plan_app`, same resolution as
                    `mix kumi.plan` (see `Mix.Tasks.Kumi.Resolve`)

  Steps 1–4 each shell out to a real `mix` subprocess (`System.cmd/3`) —
  running them in-process would pollute this task's own compiled/loaded
  state. Step 5 runs in-process (`Mix.Task.run("app.start")` first) since
  `Kumi.plan/3` is a library function, not a subprocess-shaped tool.

  Every step still runs and is reported UNLESS it structurally cannot: a
  `compile` failure means the code doesn't build, so `test`/`codegen`/
  `plan` are reported `skipped` rather than attempted. A `format` failure
  does NOT skip anything else (unformatted code still compiles) — but it
  does still block the final verdict (see `Kumi.Report`'s moduledoc).

  ## `--json` schema

      {
        "steps": [
          {"name": "format", "status": "pass" | "fail" | "skipped", "detail": "..."}
          # ... "compile", "test", "codegen", "plan", always in this order
        ],
        "verdict": "ready" | "ready_with_migration" | "blocked" | "failed",
        "plan": null | {
          "safe": <int>, "review": <int>, "dangerous": <int>,
          "operations": [
            {"description": "drop_table accounts", "level": "dangerous", "reason": "..."}
            # only REVIEW/DANGEROUS ops — see `Kumi.Report.Json`'s moduledoc
          ]
        }
      }
  """

  @shortdoc "Run mix format/compile/test/ash.codegen/kumi.plan and print a Ready-for-PR verdict"

  use Mix.Task

  alias Kumi.Report
  alias Kumi.Report.{Format, Json, Step}

  @impl Mix.Task
  def run(args) do
    {opts, _rest} =
      OptionParser.parse!(args,
        strict: [
          json: :boolean,
          skip_tests: :boolean,
          strict: :boolean,
          app: :string,
          locale: :string
        ]
      )

    env = [{"MIX_ENV", to_string(Mix.env())}]

    format_step = shell_step(:format, ["format", "--check-formatted"], env)
    compile_step = shell_step(:compile, ["compile", "--warnings-as-errors"], env)

    {test_step, codegen_step, plan_step, plan} =
      if compile_step.status == :fail do
        {skipped(:test), skipped(:codegen), skipped(:plan), nil}
      else
        test_step = test_step(opts[:skip_tests] || false)
        codegen_step = shell_step(:codegen, ["ash.codegen", "--check"], env)
        {plan_step, plan} = plan_step(opts[:app])
        {test_step, codegen_step, plan_step, plan}
      end

    report = Report.build([format_step, compile_step, test_step, codegen_step, plan_step], plan)

    # `--json` is deliberately not localized — a machine consumer's fields
    # must not change language when someone sets `locale :ja`.
    locale = Mix.Tasks.Kumi.Resolve.locale(opts[:locale], opts[:app])

    Mix.shell().info(
      if opts[:json], do: Json.encode(report), else: Format.format(report, locale: locale)
    )

    code = Report.exit_code(report, strict: opts[:strict] || false)
    if code != 0, do: exit({:shutdown, code})
  end

  defp skipped(name), do: step(name, :skipped, :step_skipped)

  defp shell_step(name, args, env) do
    {output, exit_code} = System.cmd("mix", args, stderr_to_stdout: true, env: env)
    status = if exit_code == 0, do: :pass, else: :fail
    detail_for(name, status, output)
  end

  defp detail_for(:format, :pass, _output), do: step(:format, :pass, :step_format_pass)
  defp detail_for(:compile, :pass, _output), do: step(:compile, :pass, :step_compile_pass)
  defp detail_for(:codegen, :pass, _output), do: step(:codegen, :pass, :step_codegen_pass)

  # A captured compiler or formatter diagnostic — the tool's own output,
  # with nothing in it Kumi could translate.
  defp detail_for(name, :fail, output), do: captured_step(name, :fail, truncate(output))

  # One step, its English sentence, and the key that produced it. `--json`
  # reads `detail`; the human formatter re-renders from `detail_key`.
  # Neither can drift from the other because both come from this call.
  defp step(name, status, key, bindings \\ []) do
    english = Kumi.Plan.Locale.translate(Kumi.Locale.base_locale(), key, bindings)

    %Step{name: name, status: status, detail: english, detail_key: {key, bindings}}
  end

  # A step whose detail is text Kumi captured rather than wrote.
  defp captured_step(name, status, detail),
    do: %Step{name: name, status: status, detail: detail, detail_key: nil}

  @ansi_escape ~r/\e\[[0-9;]*m/

  # ponytail: caps captured subprocess output at 20 lines so a runaway
  # compiler/test dump can't blow up the JSON payload — raise if an AI
  # agent needs the full log (it can re-run the underlying mix command).
  # `mix format --check-formatted`'s diff is colored; ANSI is stripped so
  # `--json` `detail` strings stay plain text for an AI/CI consumer.
  # `@doc false`, not `defp`: `String.split("", "\n")` returns `[""]`, not
  # `[]` — a truly empty step output never hits an empty-list branch, so
  # `[""]` is the case that must be matched explicitly. Kept public (only)
  # so this is unit-testable without shelling out a real empty-output step.
  @doc false
  def truncate(output) do
    lines = @ansi_escape |> Regex.replace(output, "") |> String.trim() |> String.split("\n")

    case lines do
      [""] -> "(no output)"
      lines when length(lines) <= 20 -> Enum.join(lines, "\n")
      lines -> lines |> Enum.take(20) |> Enum.join("\n") |> Kernel.<>("\n... (truncated)")
    end
  end

  defp test_step(true), do: %Step{name: :test, status: :skipped, detail: "skipped (by flag)"}

  defp test_step(false) do
    # No MIX_ENV override here (unlike the other subprocess steps): `mix
    # test` must run under its own preferred_cli_env (:test) so it gets
    # config/test.exs (Sandbox pool, test repo, ...) regardless of which
    # env `mix kumi.report` itself is running under. Forcing MIX_ENV=dev
    # here broke the Ecto Sandbox ("cannot invoke sandbox operation with
    # pool DBConnection.ConnectionPool") the first time this was tried
    # against spike0_crm — see the v0.4 friction log.
    {output, exit_code} = System.cmd("mix", ["test"], stderr_to_stdout: true)
    status = if exit_code == 0, do: :pass, else: :fail
    captured_step(:test, status, test_summary(output))
  end

  # Elixir 1.20's ExUnit.CLIFormatter prints "Result: N passed" (or
  # "Result: N/M passed" + a following "Failed: ..." line) — NOT the older
  # "N tests, M failures" line this originally matched against. Matching
  # the wrong format silently fell through to `truncate/1` (dumping the
  # whole captured `mix test` output as the detail) — caught running this
  # for real against spike0_crm (see the v0.4 friction log).
  defp test_summary(output) do
    case Regex.run(~r/Result:[^\n]*(?:\nFailed:[^\n]*)?/, output) do
      [line] -> line
      nil -> truncate(output)
    end
  end

  defp plan_step(app_name) do
    Mix.Task.run("app.start")
    # Kumi.Actual's introspection issues several raw Ecto queries; under a
    # host app's dev logger config (commonly :debug) those print
    # "[debug] QUERY ..." lines straight to stdout, ahead of this task's
    # own output — which corrupts `--json`'s "single JSON object on
    # stdout" contract. Silenced for the duration of this step only, then
    # restored (found running this against spike0_crm — see the v0.4
    # friction log).
    previous_level = Logger.level()
    Logger.configure(level: :warning)

    plan =
      try do
        Mix.Tasks.Kumi.Resolve.build_plan(app_name, false)
      after
        Logger.configure(level: previous_level)
      end

    status = if plan.review > 0 or plan.dangerous > 0, do: :fail, else: :pass

    detailed =
      cond do
        Enum.empty?(plan.entries) ->
          step(:plan, status, :step_plan_clean)

        status == :pass ->
          step(:plan, status, :step_plan_safe, count: plan.safe)

        true ->
          step(:plan, status, :step_plan_blocked, summary: Kumi.Plan.summary_line(plan))
      end

    {detailed, plan}
  rescue
    e ->
      {step(:plan, :fail, :step_plan_error, message: Exception.message(e)), nil}
  end
end
