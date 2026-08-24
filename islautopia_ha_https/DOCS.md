# Islautopia HTTPS for Home Assistant

**Real HTTPS for your whole Home Assistant instance — with or without internet. No domain, no DNS
account, no port forwarding.**

> **Not a Nabu Casa alternative.** This app gives you no remote access at all — the public hostname
> it uses only ever resolves to your local IP, unreachable from outside your network. It solves a
> narrower problem: real HTTPS for local access, which two-way audio needs. For genuine remote
> access use [Nabu Casa](https://www.nabucasa.com/) or your own proxy. No overlap, no conflict
> running both.

---

## Quick start

1. Install and start. No configuration.
2. Open the **Log** tab. It prints two addresses and a fingerprint.
3. Browse to whichever address you'll use. *(Optional, recommended)* set it under
   **Settings → System → Network → Home Assistant URL**.
4. *(Optional)* Want two-way audio to survive an internet outage? Open
   `http://<your-ha-ip>:8099` on each device and follow the page. See
   "[Do you need the root certificate?](#do-you-need-the-root-certificate)" first.

## The two addresses

| Address | Certificate | Works offline? | Per-device setup | Available |
|---|---|---|---|---|
| `https://<your-local-ip>:8443` | Issued by this app | **Yes, always** | Install one file, once | Always |
| `https://<your-id>.ha.doorbell.islautopia.com:8443` | Real Let's Encrypt | No — the name needs public DNS | None | With an IG Doorbell |

The second row is a hosted service rather than a feature of this app: set `ig_doorbell_id` in the
configuration to switch it on. Everything else here works without it.

Both are served on the same port simultaneously. Which one you get is decided automatically, per
connection, from the name your browser announces when the connection opens. A bare IP address
announces no name at all, which is why that case gets the local certificate.

`homeassistant.local` and `localhost` also get the local certificate. **Prefer the numeric
address**: names ending in `.local` are resolved by a neighbour-discovery mechanism that doesn't
cross network segments, so they fail exactly in the split-network setups where you most need this
to work.

## Why this app exists

Browsers only grant microphone access (`getUserMedia()`) to a page loaded over HTTPS — a *secure
context*. They judge **the page's own address**, not what the page talks to, so a doorbell's own
certificate cannot help: the page asking for the microphone came from Home Assistant. And plain
`http://192.168.x.y:8123` can never be a secure context, with no override available to you.

Built for the [Islautopia Intercom Card](https://github.com/Islautopia/islautopia-intercom-card),
but useful to **anything** needing your Home Assistant origin to be secure — third-party camera or
intercom cards included.

## Do you need the root certificate?

**Only if you want two-way audio to keep working when your internet is down.** That is its entire
purpose. Reliable connection, and fine without doorbell audio during an outage? Skip it.

Costs, plainly:

- **Per device.** No way to push it to all of them at once.
- **A real trust decision.** You're telling that device to believe certificates issued by this Home
  Assistant. Whoever could read the private key off your Home Assistant host could impersonate
  other sites to that device — which requires deep access to the host first, but is worth knowing.
- **iPhone and iPad take two steps.** Installing the profile isn't enough; iOS keeps new
  authorities off until enabled under **Settings → General → About → Certificate Trust Settings**.
  This is where nearly everyone gets stuck, with nothing on screen to explain it.
- **Firefox keeps a separate list** on every platform.

No ongoing maintenance: the root lasts ten years and the certificates it vouches for renew
themselves unattended.

## Security notes

- **The public hostname always resolves to your LOCAL IP.** It does not expose Home Assistant to
  the internet. Nobody outside your network can reach it, even knowing the name.
- **That mapping is a public DNS record.** Someone who guessed your instance id (16 random hex
  characters) could learn the private IP used inside your home. No access follows from that.
- **The public certificate's key is generated on Islautopia's server** and delivered encrypted.
  Prefer it never leaving your network? Use Home Assistant's official Let's Encrypt app (needs your
  own domain and DNS credentials). The **local** certificate's key is generated on your machine and
  never leaves it.
- **The local authority's key** is stored owner-only in the app's private storage — not the
  `/config` share, not reachable over the network.
- **The trust portal is plain HTTP on purpose.** Requiring a click-through on a certificate warning
  to fetch the certificate that removes warnings teaches the wrong reflex. The trade-off: someone
  on your network could tamper with that page, so **the fingerprint in this app's log is the
  authoritative one** — it reaches you through Home Assistant's authenticated interface. Compare
  the two before installing.
- **It does not replace Home Assistant's login.** Transport encryption only.

## Troubleshooting

**Won't start / registration error in the log.** Check outbound internet. This alone should no
longer block startup — the local path needs no internet and the log says so. If it truly refuses to
start, report it as a bug.

**Public hostname doesn't resolve.** Expected without internet. Use the local IP instead.

**Browser still warns on the local IP.** The root isn't trusted on that device yet. On iOS this is
almost always the second step above. In Firefox, import it separately.

**Certificate stale after an IP change.** Rechecked every 5 minutes, reissued automatically. Wait a
few minutes or restart the app.

**Microphone still blocked.** The address bar must show `https://` with no warning. Plain `http://`
or untrusted HTTPS can never be granted the microphone.

---

## Implementation notes

For anyone reading the source or wondering why a particular choice was made.

**Why an authority rather than one self-signed certificate.** A single self-signed certificate has
to avoid ever being regenerated, or every device that trusted it stops trusting it. That freezes
everything about it — its expiry, and the addresses it covers — which is why such setups end up
issued for ten years and never touched again. With an authority, the root is installed once and the
certificates it signs are reissued freely: when this host's addresses change, when expiry
approaches, or whenever anything else needs to change. No device is touched again.

**Lifetimes.** Root: 10 years. Leaf: 398 days, staying under the cap Apple and Chrome apply to
server certificates, reissued automatically 30 days before expiry. The root signs leaves directly,
with no intermediate — an intermediate would add no real security when both keys sit in the same
place. Same choice `mkcert` makes.

**Where the authority lives.** In the `ssl` share, under `islautopia_ha_https/ca/`, not in the
app's private volume. That volume is destroyed when the app is uninstalled, and it is a different
volume for a local copy and one installed from a repository — so keeping the authority there meant
a reinstall silently issued a new one and every device that trusted the old root stopped trusting
the app. The `ssl` share survives both, and it is where Home Assistant already keeps its own
certificate and key.

**Certificate selection.** Two Caddy site blocks on port 8443: one addressed by the public
hostname, one catch-all. Caddy matches the block by the name announced at connection start, so a
bare-IP connection — which announces nothing — lands on the catch-all and gets the local
certificate. The public block is written to the config **only when its certificate file actually
exists**, because Caddy refuses to start at all when a referenced certificate file is missing,
which would otherwise take the offline path down with it. `auto_https off` is required: without it,
naming a hostname in a site address makes Caddy attempt ACME itself.

**Name constraints were tested and deliberately left out.** A certificate authority can carry
*name constraints*, limiting what it is allowed to vouch for — which would mean that even a stolen
CA key could not be used to impersonate arbitrary websites. It was built and tested here: it
correctly rejected a forged certificate for `www.google.com` while still permitting reissue across
private address ranges, so the idea works.

It is not shipped, for one reason: support is uneven across client platforms, and the failure mode
is silent. A device that mishandles the extension simply refuses to trust the certificate, which
looks identical to "the root didn't install properly" and lands squarely on the path this app
exists to keep working. The benefit is modest by comparison — the CA key sits behind host-level
access to Home Assistant, and anyone holding that already has more than the key. Trading a
guaranteed-working primary path for a hardened secondary one is the wrong trade. Notably, the two
most widely used tools doing exactly this (`mkcert` and Caddy's own internal authority) also omit
it. Revisitable if it can be verified on real iOS and Android devices.

**Verification performed.** Real TLS handshakes against real Caddy binaries (2.10.0 and 2.11.4)
with real certificates, plus the full script executed inside the real Alpine image: no-SNI and
`homeassistant.local` both select the local certificate, the public hostname selects Let's Encrypt,
a client holding the root gets `Verify return code: 0 (ok)`, key files are 0600 inside a 0700
directory, the CA private key is unreachable over every path tried including traversal attempts,
and Caddy logs zero ACME activity.

**Still unverified.** A functional test on a real Android device. Android's companion app is known
to honor user-installed authorities — its `network_security_config.xml` declares both `system` and
`user` trust anchors — but that has not yet been confirmed end to end against this app.
