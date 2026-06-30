```markdown
# Contributing to vps-security-toolkit

This project is open to contributions. By contributing, you agree that your work will be released under the MIT License.

---

## Getting started

```bash
git clone https://github.com/<your-user>/vps-security-toolkit.git
cd vps-security-toolkit
cp .env.example .env
```

No build step, no dependencies — pure bash. You need a Linux environment to test (or a VPS/VM).

---

## Project structure

```
collectors/   # one file per domain — add new checks here
lib/          # shared helpers (html, score, notify)
run.sh        # orchestrator — sources everything, builds the HTML report
```

Each collector follows the same contract :
- A `collect_<name>()` function that populates variables
- A `render_<name>_section()` function that writes HTML to stdout
- Both must be called explicitly in `run.sh`
- Use `score_penalty <points> "<reason>"` to impact the global score

---

## Adding a new check

**1. Create or extend a collector**

```bash
# New domain → new file
collectors/07-mycheck.sh

# Existing domain → extend the relevant collector
collectors/04-bestpractices.sh
```

**2. Follow the robustness rules**

These patterns cause silent failures under `set -eu` and are banned :

```bash
# ❌ grep -c exits 1 on zero matches — kills the script
count=$(grep -c 'pattern' file)

# ✅ wrap with || true
count=$(grep -c 'pattern' file || true)
# or
count=$( { grep -c 'pattern' file || true; } )

# ❌ [[ -z "$VAR" ]] explodes if VAR starts with = | > or special chars
[[ -z "$VAR" ]] && VAR="default"

# ✅ use parameter expansion instead
VAR="${VAR:-default}"

# ❌ producer | head causes SIGPIPE under set -e
du -xhS / | sort -rh | head -10

# ✅ wrap the producer
{ du -xhS / 2>/dev/null || true; } | sort -rh | head -10

# ❌ find / without timeout blocks on Docker/containerd snapshots
find / -xdev -perm -4000 -type f

# ✅ always add timeout and exclude container paths
timeout 30 find / -xdev \
  -not -path '/var/lib/containerd/*' \
  -not -path '/var/lib/docker/*' \
  -perm -4000 -type f 2>/dev/null || true
```

**3. Test in isolation before running the full script**

```bash
# Test your collector alone with set -eu active
bash -eu -c '
source lib/html.sh
source lib/score.sh
source collectors/07-mycheck.sh
collect_mycheck
echo "DONE"
' 2>&1
```

Only submit if you see `DONE` with exit 0.

**4. Wire it into run.sh**

```bash
# In the collect section
collect_mycheck

# In the render section
render_mycheck_section

# In lib/html.sh sidebar nav
<a href="#mycheck">My check</a>
```

---

## Submitting a pull request

- One PR per logical change
- Test on a real Linux host (not just syntax check)
- Include in the PR description : what the check detects, what score penalty it applies, and on which distros you tested
- Commit messages follow this format :

```
feat(collector): short description

Longer explanation if needed.
Tested on : Ubuntu 24.04, Debian 12
```

---

## Reporting a false positive

Open an issue with :
- The file and line producing the false positive
- The output you got
- Your OS and Docker version (`uname -a`, `docker --version`)

---

## License

MIT — see [LICENSE](LICENSE).
```
