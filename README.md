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

The repositories that get them are listed in [`jetbrains-signing/.config.sh`](jetbrains-signing/.config.sh).
A repository must not also set these itself: a repository secret overrides the organisation's.

`PUBLISH_TOKEN`, the Marketplace upload token, is not part of this: it belongs to a JetBrains
account and is set per repository.

### How the signature is checked

From JetBrains' [plugin signing](https://plugins.jetbrains.com/docs/intellij/plugin-signing.html)
page:

1. The release workflow signs the plugin with the private key and uploads it with the
   certificate. The Marketplace verifies the signature, so the plugin cannot have been altered
   between the build and the upload.
2. The Marketplace then countersigns the plugin with JetBrains' own key. Installing IDEs check
   that countersignature against the JetBrains CA they ship with, and warn about a plugin that
   is unsigned or whose certificate is revoked. They never need OfficeFloor's certificate.
3. JetBrains plans for authors to upload their public key to their Marketplace profile, after
   which an upload is accepted only if its key is in the uploading account's profile. The page
   says this is "not available yet". Until it is, a self-signed certificate is not tied to any
   account: anyone with the upload token could sign with a key of their own.

So the identity is replaceable: if the key is lost, or the certificate expires, create a new
identity and upload it. Installed plugins and their updates carry on unaffected, since IDEs
check JetBrains' countersignature. Once profile keys exist, the new certificate also has to be
registered there (and, for a leaked key, the old one removed).

### The scripts

In [`jetbrains-signing/`](jetbrains-signing):

| Script | What it does |
|---|---|
| `create-signing-identity.sh` | makes the key (asking for its new password) and the certificate |
| `check-signing-files.sh` | checks the password opens the key, the certificate is the key's, and when it expires |
| `upload-signing-secrets.sh` | sets the three organisation secrets for the repositories in `.config.sh` |
| `share-signing-with-repository.sh <repo>` | gives one more repository the secrets already set |
| `show-signing-secrets.sh` | when each secret was set, which repositories read it, and any that override it |

`.config.sh` holds the organisation, the repositories and the certificate's subject and
lifetime (25 years); `.lib.sh` is shared by the scripts. Both start with a dot, so `ls` lists
only the scripts you run (`ls -a` shows them).

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
# save both files and the password in the password manager
./upload-signing-secrets.sh
rm -rf ~/officefloor-signing
```

When the Marketplace offers uploading a public key to the profile, register `chain.crt` there
with the account that holds the `PUBLISH_TOKEN`s.

### Updating

The scripts work on `~/officefloor-signing` (or `SIGNING_DIR`): restore the two files there from
the password manager first, where a step needs them.

| To | Do | Needs the files |
|---|---|---|
| give a new plugin repository the secrets | add it to `REPOS` in `.config.sh`, commit, then `./share-signing-with-repository.sh <repo>` | no |
| see what is set, and for whom | `./show-signing-secrets.sh` | no |
| check the files and the password | `./check-signing-files.sh` (warns 90 days before expiry) | yes |
| reset the repository list to `.config.sh`'s | `./upload-signing-secrets.sh` | yes |
| replace the identity: key lost, certificate expiring | `./create-signing-identity.sh` into an empty `SIGNING_DIR`, `./upload-signing-secrets.sh` (and, once profile keys exist, register the new certificate) | no (makes new ones) |
| replace a leaked key | as above; also rotate the `PUBLISH_TOKEN`s, and, once profile keys exist, remove the old certificate from the profile | no (makes new ones) |

`DRY_RUN=1 ./upload-signing-secrets.sh` shows what would be set without sending anything.
`SIGNING_PASSWORD` in the environment answers the password prompts, for scripted use.

## License

[Apache License 2.0](LICENSE).
