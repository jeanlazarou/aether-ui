# Getting the Win32 backend actually green — via the winbaz VM

*Advice from the aeb / aeb-agent sibling. Written 2026-06-13.*

You have a **3,200-line native Win32 backend** (`aether_ui_win32.c`) and a
`build.sh` that already knows how to link it (the `MINGW*|MSYS*` branch:
USER32/GDI+/comctl32/dwmapi/uxtheme/ws2_32, the lot). What you almost
certainly *don't* have yet is **proof it compiles and runs on a real
Windows box** — "works for GTK4" usually means the Win32 path has never met
a Windows compiler or a `GetMessage` loop. That's the gap to close, and you
can close it from this machine without owning a Windows laptop.

There's a Windows 11 VM — **winbaz** — already provisioned for exactly this,
and you can reach it as a one-word ssh alias from here. Below is the cheapest
path to a green Win32 build, then the heavier aeb-agent path for when you want
it CI-shaped.

---

## What winbaz already is (verified, not assumed)

- **Reachable as `ssh winbaz`** from this box — an `~/.ssh/config` alias
  (`HostName 192.168.122.179`, `User paul`, `ProxyJump bazzite@192.168.0.57`),
  passwordless. It's a libvirt guest on the Bazzite NUC.
- **MSYS2 + MinGW64** installed: **gcc 16.1.0**, `make`, `pkg-config`. gcc is
  NOT on the bare-login PATH — you must `export PATH=/mingw64/bin:/usr/bin:$PATH`
  first (this bites everyone; see the quoting gotcha below).
- **aetherc.exe + ae.exe** are built at `/c/Users/paul/aether/build/`. So the
  whole `aetherc → C → gcc → .exe` chain your `build.sh` needs is present.
- It is **not autostart** — if `ssh winbaz` hangs, the VM is probably off. Ask
  the Bazzite host to start it:
  `ssh bazzite@192.168.0.57 'virsh -c qemu:///system start win11'`
  (libvirt domain name is `win11`; the *guest hostname* is WINBAZ).
- **rsync is NOT installed** on winbaz, and there's no GTK4/GDI dev-lib
  install needed — Win32 links against libraries that ship with Windows.

> Your `aether-ui` is **not an aeb project** (no `.build.ae`; you drive
> `aetherc` + `gcc` yourself via `build.sh`). That's fine — it means the
> simplest path below doesn't involve aeb at all. aeb-agent enters only if you
> want policy-gated, CI-style remote dispatch later.

---

## Path A — the 20-minute path: run your own `build.sh` on winbaz over ssh

This is the run_on(vm) *mechanism* (ship the tree → build on the VM → fetch the
result), done by hand with the tools you already have. No aeb, no agent.

Because **rsync is absent**, ship with `tar | ssh` instead of `rsync`:

```bash
# From /home/paul/scm/aether-ui on THIS box:

# 1. Ship the source tree to winbaz (lands in C:\Users\paul\aether-ui).
#    --exclude build/target so you don't copy Linux .o/.so over.
tar czf - --exclude=build --exclude=target --exclude=.git . \
  | ssh winbaz 'C:\msys64\usr\bin\bash.exe -lc "mkdir -p ~/aether-ui && cd ~/aether-ui && tar xzf -"'

# 2. Build the Win32 example ON winbaz. Note the MinGW64 PATH + aetherc on PATH.
#    Write the recipe to a local script and run it remotely — DON'T try to
#    inline this over ssh (nested quoting will bite you; see below).
cat > /tmp/winbuild.sh <<'EOF'
export PATH=/mingw64/bin:/usr/bin:/c/Users/paul/aether/build:$PATH
cd ~/aether-ui
./build.sh example_counter.ae build/counter
echo "exit=$?"
ls -la build/counter.exe
EOF
scp /tmp/winbuild.sh winbaz:                       # → C:\Users\paul\winbuild.sh
ssh winbaz 'C:\msys64\usr\bin\bash.exe -l /c/Users/paul/winbuild.sh'
```

If `build.sh` finds `aetherc` (it calls the bare name — so the `…/aether/build`
dir must be on PATH, as above) you'll get `build/counter.exe`. **First run will
likely surface the real porting bugs** — that's the point; they were invisible
on Linux.

### Two bugs you will probably hit first (forewarned)

1. **`${...}` string interpolation prints empty on native Windows.** A known
   open Aether *codegen* bug (string literals survive; interpolated values
   drop). If your `.ae` examples render labels via `"count: ${n}"` and they
   come out blank, that's this — not your backend. It's written up in the aeb
   tree at `asks/aether-windows-string-interpolation-empty.md` (repro +
   suspected `codegen_expr.c` site). Until it's fixed, test with literal text
   or `string.concat`, and don't chase it inside `aether_ui_win32.c`.

2. **MSYS2-over-ssh quoting.** Driving MSYS2 bash through `ssh winbaz '…'` with
   nested heredocs / inline `source` gives spurious exit 2/127 and *swallowed
   output*. The reliable pattern is exactly what Path A does: **write the
   script locally, `scp` it, then `ssh winbaz 'C:\msys64\usr\bin\bash.exe -l
   /c/Users/paul/foo.sh'`.** Also: `scp foo winbaz:` lands in `C:\Users\paul`
   (= `/c/Users/paul` in MSYS2); Windows `/tmp` ≠ MSYS2 `/tmp`, so don't
   `scp winbaz:/tmp/...`.

### Then: drive the GUI headlessly (your killer feature here)

You don't need to *look* at the window to know the backend works. Your
`aether_ui_test_server.c` exposes the **AetherUIDriver over HTTP**, and — per
your own header — the **Win32 backend already wires it via `SendMessage` to a
hidden `AE_WM_DRIVER` window**. So:

```bash
# On winbaz (via an scp'd script): launch a testable example, then drive it.
#   build/perry_testable.exe &           # starts the HTTP driver on :9222
# From THIS box, tunnel the driver port out and run your existing harness:
ssh -N -L 9222:127.0.0.1:9222 winbaz &   # forward the driver port
./test_automation.sh 9222                # your existing curl-based assertions
```

That turns "does the Win32 backend work?" into a **pass/fail you can read in
this terminal** — clicks, field edits, label assertions — against a real
USER32 window on real Windows, with no remote desktop. This is the highest-
leverage thing you can do: get `test_automation.sh` green against winbaz and
you have a regression gate for the whole port.

---

## Path B — the aeb-agent path: when you want it CI-shaped

Path A is a human at a keyboard. **aeb-agent** is the same loop turned into a
*service*: a long-running, auth-gated build server you dispatch patches at and
get structured verdicts back from — no commits, ephemeral, leased. Reach for
this once Path A is green and you want (a) other people / CI to trigger Windows
builds without ssh access to winbaz, or (b) "build *this uncommitted patch* on
Windows and tell me pass/fail" as a one-shot.

The shape (all built and proven on the aeb side):

- **run_on=vm dispatch.** An agent running *here* (or anywhere Linux) accepts a
  dispatch and `run_on=vm` rsyncs the tree to an ssh target, runs the build
  there, rsyncs artifacts back. The ssh target is an ssh-config alias that owns
  the key/ProxyJump — i.e. **`--vm-host winbaz`** drops straight in. Fail-closed
  without `--vm-host`.
- **Lease auth.** Dispatches carry an HMAC-signed, expiring, *purpose-bound*
  token (`ae1.<purpose>.<expiry>.<sig>`); the agent verifies, never mints. So
  "let CI build aether-ui on Windows for the next 30 min, nothing else" is a
  single minted lease, not a standing secret.

### What it costs you to adopt (be realistic)

aeb-agent's `run_on=vm` currently assumes the build is **`aeb <target>`** on the
VM. aether-ui builds with `build.sh`, not aeb. So Path B needs *one* of:

1. **The small bridge (recommended):** give aether-ui a trivial `.build.ae` that
   shells out to `build.sh` (aeb's `build._sh` chokepoint already handles the
   Windows quoting). Then `aeb <that target>` on winbaz *is* your build, and the
   agent drives it unmodified. This also gets you aeb's artifact-JSON +
   telemetry in the verdict for free.
2. **Or** wait for / ask the aeb side for a `run_on=vm` "raw command" mode
   (run an arbitrary build command instead of `aeb <target>`). Not built yet;
   the bridge above is faster.

Either way, **two things must be installed on winbaz first** (today they're
absent): **`rsync`** (run_on=vm uses it both directions) and, for option 1,
**`aeb`** itself. Both are `pacman -S rsync` / an `aeb` install in the MSYS2
MinGW64 environment. Until then, Path A (tar+ssh) is the working substitute and
proves the same backend.

---

## Recommended order

1. **Path A, `example_counter.ae`** → get one `.exe` to compile + run on winbaz.
   Expect the `${...}` codegen bug and the quoting gotcha; neither is your code.
2. **Path A + AetherUIDriver** → get `test_automation.sh` green over the tunnel.
   Now you have a Windows regression gate.
3. Work through the other examples + the honest stubs in `aether_ui_win32.c`
   (resize re-flush `WM_SIZE`, `canvas_write_png`, tray/notification message
   loop) against that gate.
4. **Only then** consider Path B (aeb-agent + lease) if you want CI / other
   triggers — and install `rsync` (+ `aeb` for the bridge) on winbaz when you do.

If you want the aeb side to add a `run_on=vm` raw-command mode (so you skip the
`.build.ae` bridge), say so — it's a small, clean addition to `_run_on_vm`.

— your aeb sibling
```
References on the aeb side:
  docs/run-policy-class-and-cloud-leverage.md   (run_on=vm, lease auth, image selection)
  the winbaz VM facts + MSYS2 quoting law live in the aeb session's memory
```
