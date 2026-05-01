# Claude Code in Docker — Getting Started

This setup lets you run Claude Code inside a secure Docker container on the server. Claude can only access the directories you explicitly give it — nothing else on the filesystem is visible.

Each experiment lives in its own git repository. Scripts, Claude history, and custom skills are all version-controlled and backed up. Credentials are never committed.

> **Prerequisites:** Docker and Docker Compose must be installed, and the `claude_SBL` image must already be available on this server (ask your admin if it isn't).

---

## Concept: one folder = one experiment = one git repo

> [!NOTE]
> In the following replace 
> - `storm_user` with your storm username
> - `exp_1` with the name of one of your experiment

The main idea is to have Claude working in an isolated environment so that the damage caused by potential unwanted actions can be limited as much as possible, and Claude will have no access to sensible files like in `.ssh`

To this aim, for each experiment only three folders are mounted inside the container, and therefore are allowed for Claude to act upon:

- a script folder in read/write mode 
- (one or more) data folder in read only mode
- a `.claude` directory where history, skills and other files useful to claude can be placed

Crucially, for maximum security, the user will need to authenticate with Claude every time a session starts, and the credentials - already in the `.gitignore` - will be deleted when the session ends.

These three folders live inside a specific directory in you `/home/storm_user` folder, named with an ID of the experiment such as `exp_1`.

> [!IMPORTANT]
> Importantly, you should also prepare a github repo for this folder, so that in case of disasters to the server (caused by Claude or other events), you can restore all the scripts up to the latest commit/push from the github repo.

Here's an example

```
/home/users/storm_user/
├── exp_1/                    ← git repo for the exp_1 experiment
│   ├── .gitignore             ← excludes credentials only
│   ├── docker-compose.yml     ← edit path(s) to the data dir(s)
│   ├── scripts/               ← your analysis scripts — tracked in git
│   └── claude_state/          ← Claude history & skills — tracked in git
│       └── .credentials.*     ← excluded by .gitignore, never committed
│
└── exp_2/                      ← git repo for the guts experiment
    ├── .gitignore
    ├── docker-compose.yml
    ├── scripts/
    └── claude_state/
```

Everything inside the experiment folder (except credentials) is committed to git. If the server is lost, you recover with a `git clone`.

---

## One-time setup (per user)

### Export your group ID

`$UID` is set automatically by bash, but `$GID` may not be. Add this to your shell config so it's always available:

```bash
echo 'export GID=$(id -g)' >> ~/.bashrc
source ~/.bashrc
```

---

## Setting up a new experiment
**WE WILL PROVIDE A VIDEO TUTORIAL FOR THIS**

### Step 0 - Create a new repo on github with the name of the experiment
Go to github.com and log into your account. Make sure that on github.com you have already registered a _public_ key created on the server (storm), as you will need it to push and pull from the github account to your local repo.

For instance in our case we could call it `exp_1`

### Step 1 — Create the experiment folder and initialise git

```bash
mkdir /home/users/storm_user/exp_1
cd /home/users/storm_user/exp_1
git init
```

### Step 2 — Copy the template files into the folder

Copy these four files from the template (provided by your admin):

```
.gitignore
docker-compose.yml
```

Then create the scripts directory:

```bash
mkdir scripts
```

The `claude_state/` directory is created automatically the first time you run the container.

### Step 3 — Edit the one placeholder in `docker-compose.yml`

Only the data path needs to change — scripts and claude_state use relative paths and are already correct:

```yaml
# ⚠️  Edit this line only:
- /path/to/your/mri-data:/workspace/data:ro
```

For example:

```yaml
- /data00/storm_user/exp_1/data_work:/workspace/data:ro
```

Save the file.

### Step 4 — Connect to GitHub and make the first commit

```bash
git add .gitignore docker-compose.yml scripts/
git commit -m "init exp_1 experiment"
git remote add origin https://github.com/storm_user/exp_1.git
git push -u origin main
```

---

## Starting a Claude session

From the experiment folder:

```bash
cd /home/users/storm_user/exp_1
docker compose run --rm claude_SBL
```

That's it. Claude Code starts with access to your scripts and data for this experiment.

- **Every session:** Claude Code will display a login URL. Open it in your browser, log in with your Anthropic account, and the session starts. *(Login is required each session — credentials are intentionally not saved.)*

---

## What Claude can and cannot do

| Location | Claude's access |
|---|---|
| `/workspace/scripts/` | ✅ Read and write — Claude edits your scripts here |
| `/workspace/data/` | 👁️ Read only — cannot modify or delete data |
| Everything else | 🚫 Not visible — completely outside the container |

---

## Committing after a session

After working with Claude, commit from the host terminal:

```bash
cd /home/users/storm_user/exp_1
git add -A
git commit -m "session: describe what was done"
git push
```

This captures both new/modified scripts and any updates to Claude's history and skills. Credentials are automatically excluded by `.gitignore`.

> **Note:** Git is not installed inside the container — Claude cannot run `git push` during a session. All git operations happen from your host terminal.

---

## Experiment isolation

Each experiment folder is a completely independent git repo. Claude working on `exp_1` has no access to `guts` data, scripts, or history — and vice versa.

If you want to share a custom command ("skill") between experiments, copy the relevant file from one `claude_state/commands/` directory to another on the host.

---

## Frequently asked questions

**Can Claude delete my data?**
No. The data volume is mounted read-only (`:ro`). Any write or delete attempt is rejected by the kernel.

**Can Claude push credentials to GitHub?**
No — for two reasons: (1) git is not installed inside the container, so Claude cannot run any git commands; (2) even if you run git from the host, the `.gitignore` excludes all known credential file names.

**Can Claude access files outside my scripts and data directories?**
No. Docker's isolation ensures only the paths listed in `docker-compose.yml` are visible inside the container.

**What is `claude_state/`?**
Claude's working memory for this experiment: conversation history, custom commands, and settings. It is committed to git (minus credentials) so it survives a server failure. Delete it if you want to clear Claude's history for this experiment.

**Why do I need to log in every session?**
Credentials are intentionally not saved between sessions for security. Your history and custom commands are preserved in `claude_state/` and are committed to git.
