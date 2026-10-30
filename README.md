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

### The scripts

In [`jetbrains-signing/`](jetbrains-signing):

| Script | What it does |
|---|---|
| `create-signing-identity.sh` | makes the key (asking for its new password) and the certificate, once |
| `check-signing-files.sh` | checks the password opens the key, the certificate is the key's, and when it expires |
| `upload-signing-secrets.sh` | sets the three organisation secrets for the repositories in `config.sh` |
| `share-signing-with-repository.sh <repo>` | gives one more repository the secrets already set |
| `show-signing-secrets.sh` | when each secret was set, which repositories read it, and any that override it |
| `renew-signing-certificate.sh` | extends the certificate on the same key, before it expires |

`config.sh` holds the organisation, the repositories and the certificate's subject; `lib.sh`
is shared by the scripts.

### Access

Organisation secrets need GitHub's `admin:org` scope. The scripts that touch them
(`upload-signing-secrets.sh`, `share-signing-with-repository.sh`, `show-signing-secrets.sh`)
get it in one way only: a temporary token made for that run. `gh`'s own login is never given
the scope, and a `GH_TOKEN` already set is ignored.

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
# asks for a new password, makes ~/officefloor-signing/{private_encrypted.pem,chain.crt}
./create-signing-identity.sh
# now save both files and the password in the password manager
./upload-signing-secrets.sh
rm -rf ~/officefloor-signing
```

### Updating

The scripts work on `~/officefloor-signing` (or `SIGNING_DIR`): restore the two files there from
the password manager first, where a step needs them.

| To | Do | Needs the files |
|---|---|---|
| give a new plugin repository the secrets | add it to `REPOS` in `config.sh`, commit, then `./share-signing-with-repository.sh <repo>` | no |
| see what is set, and for whom | `./show-signing-secrets.sh` | no |
| check the files and the password | `./check-signing-files.sh` (warns 90 days before expiry) | yes |
| extend the certificate before it expires (10 years) | `./renew-signing-certificate.sh`, save the new `chain.crt`, `./upload-signing-secrets.sh` | yes |
| reset the repository list to `config.sh`'s | `./upload-signing-secrets.sh` | yes |
| replace a leaked key | `./create-signing-identity.sh` into an empty `SIGNING_DIR`, `./upload-signing-secrets.sh`; check JetBrains' plugin-signing documentation on changing a plugin's certificate first | yes |

`DRY_RUN=1 ./upload-signing-secrets.sh` shows what would be set without sending anything.
`SIGNING_PASSWORD` in the environment answers the password prompts, for scripted use.

## License

[Apache License 2.0](LICENSE).
