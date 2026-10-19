# tools/audit - measurement and report scripts

These used to live in `tools/probe/`. They PRINT numbers (render cost, curves, name lengths, sprite gaps...)
and have no pass/fail verdict, so `python tools/probe_run.py --all` reported each as a failure and
"all probes pass" meant nothing. A probe asserts and prints a PASS line; an audit measures. Run one with:

    godot --headless --path . --script res://tools/audit/<name>.gd

If an audit turns out to carry a real assertion, give it a PASS/FAIL verdict line and move it back to
`tools/probe/`.
