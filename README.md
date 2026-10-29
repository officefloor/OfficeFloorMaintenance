# OfficeFloor Maintenance

Scripts for looking after what the OfficeFloor organisation shares across its repositories.
Nothing secret is kept here: the scripts make and upload secrets, and the originals live in the
password manager.

## JetBrains plugin signing

Every OfficeFloor IntelliJ plugin is signed with one OfficeFloor identity: an encrypted RSA key
and a self-signed certificate (`CN=OfficeFloor`). They are held as **organisation** secrets, so
each plugin repository's release workflow reads the same three:

| Secret | What it is |
|---|---|
| `CERTIFICATE_CHAIN` | the certificate, `chain.crt` |
| `PRIVATE_KEY` | the encrypted key, `private_encrypted.pem` |
| `PRIVATE_KEY_PASSWORD` | the key's password |

The repositories that get them are listed in [`jetbrains-signing/config.sh`](jetbrains-signing/config.sh).
A repository must not also set these itself: a repository secret overrides the organisation's.

Signing is optional for the JetBrains Marketplace (it countersigns every approved upload
itself), but once a plugin has been published signed, later versions must be signed by the
same identity. So make it once, keep it, and renew rather than replace it.

`PUBLISH_TOKEN`, the Marketplace upload token, is not part of this: it belongs to a JetBrains
account and is set per repository.

### Access

Organisation secrets need GitHub's `admin:org` scope. The scripts that touch them (`upload.sh`,
`add-repo.sh`, `status.sh`) get it in one way only: a temporary token made for that run.
`gh`'s own login is never given the scope, and a `GH_TOKEN` already set is ignored.

Each run walks you through it:

1. Press Enter, and GitHub's *New personal access token (classic)* page opens with the note
   and the `admin:org` scope filled in.
2. Set *Expiration* to *Custom*, tomorrow, check `admin:org` is the only scope, and generate.
3. Paste the token at the prompt (it is not shown). The script checks it carries `admin:org`,
   uses it for that run only, and when it ends reminds you to delete it at
   https://github.com/settings/tokens.

Run them in your own terminal: they prompt for passwords and open the browser. You must be an
owner of the organisation.

### First time

```bash
cd jetbrains-signing
./generate.sh      # asks for a new password, makes ~/officefloor-signing/{private_encrypted.pem,chain.crt}
                   # save both files and the password in the password manager
./upload.sh        # checks them, then sets the three organisation secrets
rm -rf ~/officefloor-signing
```

### Updating

The scripts work on `~/officefloor-signing` (or `SIGNING_DIR`): restore the two files there from
the password manager first, where a step needs them.

| To | Do | Needs the files |
|---|---|---|
| give a new plugin repository the secrets | add it to `REPOS` in `config.sh`, commit, then `./add-repo.sh <repo>` | no |
| see what is set, and for whom | `./status.sh` | no |
| check the files and the password | `./check.sh` (warns 90 days before expiry) | yes |
| extend the certificate before it expires (10 years) | `./renew.sh`, save the new `chain.crt`, `./upload.sh` | yes |
| reset the repository list to `config.sh`'s | `./upload.sh` | yes |
| replace a leaked key | `generate.sh` into an empty `SIGNING_DIR`, `./upload.sh`; check JetBrains' plugin-signing documentation on changing a plugin's certificate first | yes |

`DRY_RUN=1 ./upload.sh` shows what would be set without sending anything.
`SIGNING_PASSWORD` in the environment answers the password prompts, for scripted use.

## License

[Apache License 2.0](LICENSE).
