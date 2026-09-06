#!/usr/bin/bash
# Container signing policy.
#
# The workflow signs with cosign in legacy simple-signing mode
# (--new-bundle-format=false), still the only format rpm-ostree and bootc verify. For
# the installed system to verify its own upgrades, three things must be in the image:
#
#   1. the public key             /etc/pki/containers/<image>.pub
#   2. sigstore-attachment hint   /etc/containers/registries.d/<registry>.yaml
#   3. a policy entry             /etc/containers/policy.json
#
# The base has all three for ghcr.io/ublue-os. A parallel set is added for this
# image's registry, merged with jq so the ublue and Red Hat entries survive. Without
# it, image-info.json's `ostree-image-signed:` ref cannot be satisfied and the ISO
# kickstart's `bootc switch --enforce-container-sigpolicy` fails.
source "${CTX}/build_files/lib/common.sh"

readonly POLICY="/etc/containers/policy.json"
# Registry host + namespace: exactly the scope cosign signs.
readonly SCOPE="${IMAGE_REGISTRY}"
readonly KEY_DEST="/etc/pki/containers/${IMAGE_NAME}.pub"
readonly PUBKEY="${CTX}/cosign.pub"

log "Installing container signing policy for ${SCOPE}"

if [[ ! -s "${PUBKEY}" ]] || grep -qi 'placeholder' "${PUBKEY}"; then
    # Refuse rather than warn: an image demanding a signature but shipping no key
    # cannot be upgraded at all.
    die "cosign.pub is missing or still a placeholder.
    Generate a keypair and commit the public half:
      cosign generate-key-pair
      mv cosign.pub cosign.pub && gh secret set SIGNING_SECRET < cosign.key
    then delete cosign.key. See README.md 'Signing'."
fi

install -Dm0644 "${PUBKEY}" "${KEY_DEST}"
info "public key -> ${KEY_DEST}"

# cosign stores signatures as an OCI attachment, not in a lookaside server.
cat >"/etc/containers/registries.d/${IMAGE_NAME}.yaml" <<EOF
docker:
  ${SCOPE}:
    use-sigstore-attachments: true
EOF
info "registries.d/${IMAGE_NAME}.yaml written"

[[ -f "${POLICY}" ]] || die "${POLICY} missing in base image"

tmp="$(mktemp)"
jq \
    --arg scope "${SCOPE}" \
    --arg key   "${KEY_DEST}" \
    '.transports.docker[$scope] = [
        {
            "type": "sigstoreSigned",
            "keyPath": $key,
            "signedIdentity": { "type": "matchRepository" }
        }
     ]' \
    "${POLICY}" >"${tmp}"
mv -f "${tmp}" "${POLICY}"
chmod 0644 "${POLICY}"

# jq object assignment does not disturb the other scopes; assert that.
for keep in "ghcr.io/ublue-os" "registry.redhat.io" ""; do
    jq -e --arg k "${keep}" '.transports.docker | has($k)' "${POLICY}" >/dev/null \
        || die "policy.json lost the '${keep}' docker scope"
done
info "policy.json scopes: $(jq -r '.transports.docker | keys | join(", ")' "${POLICY}")"
