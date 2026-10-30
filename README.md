# OfficeFloor Maintenance

Scripts for setting up what the OfficeFloor organisation shares across its repositories.
Nothing secret is kept here: the scripts put secrets into GitHub.

## Publishing IntelliJ plugins to the JetBrains Marketplace

```bash
./setup-jetbrains-publishing.sh
```

Run it in your own terminal (it asks for passwords and tokens, and opens the browser). It sets
the organisation secrets that the plugin repositories' release workflows read, for the
repositories listed in [`jetbrains-plugin-repositories.txt`](jetbrains-plugin-repositories.txt):

| Secret | What it is |
|---|---|
| `CERTIFICATE_CHAIN` | the OfficeFloor certificate (self-signed, `CN=OfficeFloor`, 25 years) |
| `PRIVATE_KEY` | its encrypted RSA key |
| `PRIVATE_KEY_PASSWORD` | the key's password |
| `PUBLISH_TOKEN` | a JetBrains Marketplace token, which uploads the plugins |

It asks three questions, each of which can be answered no:

1. **Set up the signing keys?** It asks for a password, makes the key and certificate, and sets
   the first three secrets. It writes the certificate, which is public, to
   `jetbrains-signing-certificate.crt` here, to commit. It can keep a copy of the private key
   for a password manager; otherwise the key is deleted.
2. **Set up `PUBLISH_TOKEN`?** It opens the Marketplace's token page; you generate a token
   with the account that publishes the plugins, and paste it.
3. **Update the repositories with access?** Makes the repositories that may read the secrets
   exactly those in the list (for any secret not just set, which already has the list).

A secret set in step 1 or 2 is readable by the listed repositories only.

**Adding a plugin repository later:** add its name to `jetbrains-plugin-repositories.txt`,
commit, run the script, and answer no, no, yes. Removing a name works the same way.

Changing secrets needs GitHub's `admin:org` scope, which `gh`'s login does not have and is not
given. The first time the script is to change something, it opens GitHub's new-token page
with `admin:org` filled in: set the expiry to tomorrow, generate, and paste the token. It is
used for that run only (all three steps share it), and at the end the script reminds you to
delete it. You must be an owner of the organisation.

A repository must not set its own secret of the same name: it would override the organisation's.

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
   says this is "not available yet", and there is no API for it. When it is offered, add
   `jetbrains-signing-certificate.crt` to the profile of the account that publishes.

So the identity is replaceable: if the key is lost or leaked, or the certificate nears its
expiry, run the signing step again (it makes a new identity and replaces the secrets); for a
leak, also replace `PUBLISH_TOKEN`. Installed plugins and their updates carry on unaffected,
since IDEs check JetBrains' countersignature.

`DRY_RUN=1 ./setup-jetbrains-publishing.sh` makes a throwaway key and shows what would be set,
sending nothing.

## License

[Apache License 2.0](LICENSE).
