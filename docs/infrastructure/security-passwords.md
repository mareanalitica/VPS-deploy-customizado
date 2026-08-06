# 🔒 Area: Infrastructure & DevOps — Security & Backup Policy

[← Back to Documentation Hub](../README.md)

---

## 🔑 Automated Password Generation & Variable Resolution (`manage-env.js`)

To eliminate hardcoded credentials or manual secret configuration, the repository utilizes **`setup/scripts/manage-env.js`**.

### 🎯 How Password Generation & Resolution Works

When executing:
```bash
npm run setup
# or to force regeneration when backups exist:
node setup/scripts/manage-env.js --force
```

1. **Secret Key Detection:** Scans `.env` for key patterns containing:
   * `PASSWORD`, `PASS`, `SECRET`, `KEY`, `TOKEN`, `AUTH`
2. **Cryptographic Random Generation:** Empty secret values are populated with 24–32 character cryptographically secure strings (`crypto.randomBytes()`).
3. **Variable Resolution (`${VAR}`):** Automatically resolves references like `${MONGO_INITDB_ROOT_PASSWORD}` in sub-app `.env` files using values from the root `.env`.
4. **Volume Safety & Force Mode:** If existing backups are detected, `manage-env.js` blocks accidental password regeneration to preserve database compatibility unless `--force` is explicitly provided.
5. **Local Persistence:** Newly generated credentials are saved into the local `.env` file on the VPS.

---

## 📦 Automated Backup Policy

### 1. Environment Backups (`setup/backups/`)
- **Trigger:** Whenever `.env` exists and contains pre-populated secrets prior to an edit.
- **Naming Format:** Timestamped in ISO format (`YYYY-MM-DD`) and an appended `UUID` or target name (`env_bkp_<TARGET>_<TIMESTAMP>.env`).
- **Git Protection:** The `setup/backups/` directory and `.env` files are ignored in `.gitignore`, preventing accidental git leaks.

### 2. Database Volume Backups (`setup/scripts/backup-volumes.sh`)
Execute via:
```bash
npm run backup:volumes
# or
bash setup/scripts/backup-volumes.sh
```
- **MongoDB:** Dumped via `mongodump --archive --gzip`.
- **PostgreSQL:** Dumped via `pg_dumpall | gzip`.
- **Redis:** Snapshot triggered via `redis-cli BGSAVE` and copied (`dump.rdb`).
- **Storage Location:** Saved under `setup/backups/volumes/YYYY-MM-DD_HHMMSS/`.
- **Retention Policy:** Automatically purges backup directories older than 7 days (`mtime +7`).

