# openGym Helm chart

A Helm chart for running openGym on Kubernetes. It creates the same resources as the plain
manifests in [SELF_HOSTING_KUBERNETES.md](../../docs/SELF_HOSTING_KUBERNETES.md), but the
hostname, images, Gateway and resources are values instead of edits to YAML files. Read
[SELF_HOSTING.md](../../docs/SELF_HOSTING.md) first: the passkey requirement (HTTPS, `RP_ID`,
`ORIGIN`), the settings in `.env.example` and the backup advice apply here unchanged.

What the chart creates:

- 2 PVCs: `opengym-data` (users, passkeys, workouts, uploads — **back this one up**) and
  `opengym-media` (the exercise images, downloaded again if lost).
- 1 Deployment running the API and the web container in a single pod, with an initContainer that
  downloads the exercise media (~140 MB) on first start. It stays at one replica with the
  `Recreate` strategy: the API's data is files on a `ReadWriteOnce` volume, and two API processes
  must never write them at once.
- 1 Service, `opengym`, on port 80, pointing at the web container.
- Optionally an HTTPRoute for the Gateway API, a cert-manager Certificate for the hostname, and a
  ReferenceGrant so a Gateway in another namespace can read that certificate.

## Install

Put your settings in a values file. The least you need is your hostname, twice:

```yaml
# my-values.yaml
api:
  rpID: gym.example.com
  origin: https://gym.example.com
```

The chart is published to GHCR next to the images, so there is no repo to add:

```bash
helm install opengym oci://ghcr.io/duartesantos8/charts/opengym \
  --namespace fitness --create-namespace -f my-values.yaml
```

Add `--version 0.1.0` to pin a chart version. To install from a clone instead, use the chart's
directory, `chart/openGym`, in place of the `oci://` address.

That gives you a running pod and a Service, but nothing reaches it from outside the cluster yet:
see [Exposing it](#exposing-it). To try it before that, port-forward the Service:

```bash
kubectl --namespace fitness port-forward svc/opengym 8080:80
```

Passkeys only work there if `api.rpID` is `localhost` (see SELF_HOSTING.md), so set it that way
for a quick test, or use guest mode.

Notes:

- Resource names come from the chart, not the release name, so install one release per namespace.
- The PVCs use the cluster's default StorageClass.
- `helm uninstall` leaves `opengym-data` in place, so your data survives it; `opengym-media` is
  deleted and downloaded again on the next install. Installing again with the same release name
  and namespace picks the old claim back up. To really remove everything, delete it yourself:
  `kubectl --namespace fitness delete pvc opengym-data`.

## Exposing it

openGym needs HTTPS on a real hostname for passkeys, so the Gateway or Ingress in front of it has
to terminate TLS. The chart can create an HTTPRoute for the
[Gateway API](https://gateway-api.sigs.k8s.io); this was tested with
[Envoy Gateway](https://gateway.envoyproxy.io) and [cert-manager](https://cert-manager.io).

```yaml
httpRoute:
  enabled: true
  parentRefs:
    - name: eg
      namespace: envoy-gateway-system
      sectionName: https
  tlsSecret: opengym-tls
  certManager:
    enabled: true
    issuerRef:
      kind: ClusterIssuer
      name: letsencrypt
  referenceGrant:
    enabled: true
    gatewayNamespace: envoy-gateway-system
```

- `parentRefs` is your cluster's Gateway, not the chart's: change the name, namespace and listener
  to match it.
- The route's hostname is `api.rpID`; there is no separate setting for it.
- `certManager` asks cert-manager for a certificate for `api.rpID`, stored in `tlsSecret`. Leave
  it off if you create that Secret some other way.
- `referenceGrant` is only needed when the Gateway's listener reads `tlsSecret` from openGym's
  namespace. If the listener carries its own (e.g. wildcard) certificate, leave it off.

No Gateway API? The chart has no Ingress template, but an Ingress of your own pointing at the
`opengym` Service on port 80 works as well.

## Settings

Settings are environment variables on the `api` container, named as in `.env.example`. `PORT`,
`DATA_DIR`, `RP_ID` and `ORIGIN` are set by the chart; add anything else to `api.extraEnv`:

```yaml
api:
  extraEnv:
    - name: INVITE_ONLY
      value: "1"
    - name: FIRST_USER_ADMIN
      value: "1"
```

`extraEnv` is a list of ordinary container env entries, so `valueFrom` works too if you'd rather
keep a setting in a ConfigMap or Secret. None of the settings are secrets, though: the push keys
are generated into `vapid.json` and AI Coach credentials are encrypted into `coach.json`, both on
the `opengym-data` volume.

Lists are not merged by Helm: if you set `api.extraEnv` in two values files, the last one wins.
`web.extraEnv` works the same way for the `web` container.

## Values

| Value | Default | What it does |
|---|---|---|
| `api.rpID` | `opengym.example.com` | Hostname passkeys are bound to; also the HTTPRoute hostname. |
| `api.origin` | `https://opengym.example.com` | The full URL people open. `https://` + `api.rpID`. |
| `api.repository`, `api.tag` | `ghcr.io/duartesantos8/opengym-api`, the chart's `appVersion` | API image. |
| `web.repository`, `web.tag` | `ghcr.io/duartesantos8/opengym-web`, the chart's `appVersion` | Web image. If you set a tag, set the same one as the API's. |
| `api.port` | `3000` | Port the API listens on inside the pod. |
| `api.dataDir` | `/data` | Where the data volume is mounted in the API container. |
| `web.nginxPort` | `80` | Port nginx listens on, and the Service's port. |
| `web.port` | `3000` | Port nginx proxies `/api` to. Must match `api.port`. |
| `api.extraEnv`, `web.extraEnv` | `[]` | Extra environment variables, see [Settings](#settings). |
| `api.resources`, `web.resources`, `mediaInit.resources` | 128Mi request, 256Mi limit | Memory for each container. Set to `null` to leave it unset. |
| `mediaInit.repository`, `mediaInit.tag` | `alpine/git`, `2.52.0` | Image for the media download. |
| `volumes.data.name`, `volumes.data.claimSize` | `opengym-data`, `2Gi` | The data PVC. |
| `volumes.media.name`, `volumes.media.claimSize` | `opengym-media`, `2Gi` | The media PVC. |
| `httpRoute.*` | off | See [Exposing it](#exposing-it). |
| `imagePullSecrets`, `nodeSelector`, `tolerations`, `affinity` | empty | The usual pod settings, passed through as written. |

## Updating

Each version of the chart deploys one openGym release, its `appVersion` (`1.3.10` for this
one), and the API and the web image always run that same release. To update, read the release
notes and upgrade to the new chart:

```bash
helm upgrade opengym oci://ghcr.io/duartesantos8/charts/opengym --namespace fitness -f my-values.yaml
```

To run a release the chart doesn't default to, set `api.tag` and `web.tag` in your values file,
both to the same version. Remember they're there: a pinned tag stays pinned when you later upgrade
the chart. Pinning to `latest` instead means a restarted pod can come back on a version you never
chose. Because of the `Recreate` strategy, the old pod stops before the new one starts, so expect
a few seconds of downtime.

## Other notes

- The AI Coach with an API key works on the published API image; the Claude and Codex sign-in
  providers need the `coach` build target, which is not published. Build it yourself (see
  [AI_COACH.md](../../docs/AI_COACH.md)) and point `api.repository` and `api.tag` at it.
- **Client addresses.** Behind a Gateway, the API sees the gateway's pod as every visitor's
  address, so the sign-in throttle acts on the whole instance at once. `TRUST_PROXY` is left off
  on purpose. The reasons, and what it takes to get real visitor addresses, are in
  [SELF_HOSTING_KUBERNETES.md](../../docs/SELF_HOSTING_KUBERNETES.md).
