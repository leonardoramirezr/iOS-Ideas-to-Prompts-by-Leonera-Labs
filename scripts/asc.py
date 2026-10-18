#!/usr/bin/env python3
"""Utilidades de firma para CI. Solo stdlib + `openssl` (JWT ES256) y `security` (macOS).

Comandos:
  check                        Comprueba que la clave de App Store Connect funciona y que
                               hay al menos un dispositivo iOS registrado.
  keychain-dev-serials         Imprime los seriales de los certificados "Apple Development"
                               del llavero, uno por línea.
  revoke-certificates SERIAL…  Revoca por la API los certificados con esos seriales.
  verify-ipa IPA [--json F]    Verifica que cada bundle lleva un embedded.mobileprovision
                               Ad Hoc y muestra cuántos dispositivos incluye.

Variables de entorno: ASC_KEY_ID, ASC_ISSUER_ID y ASC_KEY_PATH (ruta al .p8).
"""

import base64
import json
import os
import plistlib
import re
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile

API = "https://api.appstoreconnect.apple.com"
OPENSSL = os.environ.get("OPENSSL", "openssl")


def fail(message):
    print(f"::error::{message}", file=sys.stderr)
    sys.exit(1)


# --- JWT ES256 ---------------------------------------------------------------

def b64url(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw_signature(der):
    """Convierte una firma ECDSA DER (SEQUENCE de dos INTEGER) a r||s de 64 bytes."""
    def read_length(data, index):
        length = data[index]
        index += 1
        if length & 0x80:
            count = length & 0x7F
            length = int.from_bytes(data[index:index + count], "big")
            index += count
        return length, index

    if der[0] != 0x30:
        raise ValueError("firma DER inválida")
    _, index = read_length(der, 1)
    parts = []
    for _ in range(2):
        if der[index] != 0x02:
            raise ValueError("firma DER inválida")
        length, index = read_length(der, index + 1)
        value = der[index:index + length].lstrip(b"\x00")
        parts.append(value.rjust(32, b"\x00"))
        index += length
    return parts[0] + parts[1]


def make_token():
    key_id = os.environ.get("ASC_KEY_ID", "")
    issuer = os.environ.get("ASC_ISSUER_ID", "")
    key_path = os.environ.get("ASC_KEY_PATH", "")
    if not key_id or not issuer or not key_path:
        fail("Faltan ASC_KEY_ID, ASC_ISSUER_ID o ASC_KEY_PATH.")
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {"iss": issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}"
    result = subprocess.run(
        [OPENSSL, "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(),
        capture_output=True,
    )
    if result.returncode != 0:
        fail("openssl no pudo firmar el JWT. ¿ASC_KEY_P8 contiene la clave .p8 completa? "
             + result.stderr.decode(errors="replace").strip())
    return f"{signing_input}.{b64url(der_to_raw_signature(result.stdout))}"


# --- API ---------------------------------------------------------------------

_token = None


def api(method, path, params=None):
    global _token
    if _token is None:
        _token = make_token()
    url = path if path.startswith("http") else API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    request = urllib.request.Request(url, method=method, headers={"Authorization": f"Bearer {_token}"})
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            body = response.read()
            return json.loads(body) if body else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        try:
            errors = json.loads(detail).get("errors", [])
            detail = "; ".join(f"{e.get('title')}: {e.get('detail')}" for e in errors) or detail
        except ValueError:
            pass
        raise RuntimeError(f"{method} {path} → HTTP {error.code}: {detail}") from None


def paginate(path, params):
    response = api("GET", path, params)
    yield from response.get("data", [])
    while response.get("links", {}).get("next"):
        response = api("GET", response["links"]["next"])
        yield from response.get("data", [])


# --- Comandos ----------------------------------------------------------------

def command_check(_args):
    try:
        devices = list(paginate("/v1/devices", {
            "filter[platform]": "IOS",
            "filter[status]": "ENABLED",
            "limit": "200",
        }))
    except RuntimeError as error:
        fail(f"La clave de App Store Connect no funciona: {error}")
    print(f"Clave de App Store Connect válida. Dispositivos iOS registrados: {len(devices)}")
    for device in devices:
        attributes = device.get("attributes", {})
        print(f"  - {attributes.get('name')} ({attributes.get('deviceClass')}, {attributes.get('model') or 'modelo desconocido'})")
    if not devices:
        fail("No hay ningún dispositivo iOS registrado en Apple Developer. Registra el UDID de tu iPhone.")


def normalize_serial(serial):
    return serial.strip().upper().lstrip("0")


def command_keychain_dev_serials(_args):
    result = subprocess.run(
        ["security", "find-certificate", "-a", "-c", "Apple Development", "-p"],
        capture_output=True, text=True,
    )
    pems = re.findall(r"-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----", result.stdout, re.S)
    serials = set()
    for pem in pems:
        output = subprocess.run([OPENSSL, "x509", "-noout", "-serial"], input=pem, capture_output=True, text=True)
        match = re.search(r"serial=([0-9A-Fa-f]+)", output.stdout)
        if match:
            serials.add(normalize_serial(match.group(1)))
    for serial in sorted(serials):
        print(serial)


def command_revoke_certificates(args):
    wanted = {normalize_serial(serial) for serial in args if serial.strip()}
    if not wanted:
        print("No hay certificados nuevos que revocar.")
        return
    certificates = list(paginate("/v1/certificates", {"limit": "200"}))
    revoked = set()
    for certificate in certificates:
        attributes = certificate.get("attributes", {})
        serial = normalize_serial(attributes.get("serialNumber", ""))
        if serial not in wanted:
            continue
        name = attributes.get("displayName") or attributes.get("name")
        api("DELETE", f"/v1/certificates/{certificate['id']}")
        revoked.add(serial)
        print(f"Revocado: {name} ({attributes.get('certificateType')}, serial {serial})")
    for serial in sorted(wanted - revoked):
        print(f"::warning::No se encontró en App Store Connect el certificado con serial {serial}.")


def decode_profile(path):
    result = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr.decode(errors="replace").strip())
    return plistlib.loads(result.stdout)


def command_verify_ipa(args):
    if not args:
        fail("Uso: asc.py verify-ipa IPA [--json SALIDA]")
    ipa = args[0]
    json_out = args[args.index("--json") + 1] if "--json" in args else None
    summary = []
    with tempfile.TemporaryDirectory() as tmp:
        with zipfile.ZipFile(ipa) as archive:
            archive.extractall(tmp)
        bundles = []
        for root, dirs, _files in os.walk(os.path.join(tmp, "Payload")):
            for name in dirs:
                if name.endswith((".app", ".appex")):
                    bundles.append(os.path.join(root, name))
        if not bundles:
            fail("El IPA no contiene ningún bundle .app.")
        ok = True
        for bundle in sorted(bundles):
            label = os.path.relpath(bundle, os.path.join(tmp, "Payload"))
            profile_path = os.path.join(bundle, "embedded.mobileprovision")
            if not os.path.exists(profile_path):
                print(f"::error::{label} no lleva embedded.mobileprovision")
                ok = False
                continue
            profile = decode_profile(profile_path)
            devices = profile.get("ProvisionedDevices", [])
            entitlements = profile.get("Entitlements", {})
            is_ad_hoc = bool(devices) and not profile.get("ProvisionsAllDevices") \
                and not entitlements.get("get-task-allow", False)
            print(f"{label}: perfil «{profile.get('Name')}» ({profile.get('UUID')}), "
                  f"{len(devices)} dispositivos, caduca {profile.get('ExpirationDate')}")
            if not is_ad_hoc:
                print(f"::error::El perfil de {label} no es Ad Hoc.")
                ok = False
            summary.append({"bundle": label, "profile": profile.get("Name"), "devices": len(devices)})
        if not ok:
            sys.exit(1)
    devices = min(item["devices"] for item in summary)
    print(f"Perfiles Ad Hoc correctos. Dispositivos incluidos: {devices}")
    if json_out:
        with open(json_out, "w") as handle:
            json.dump({"devices": devices, "bundles": summary}, handle, indent=2)


COMMANDS = {
    "check": command_check,
    "keychain-dev-serials": command_keychain_dev_serials,
    "revoke-certificates": command_revoke_certificates,
    "verify-ipa": command_verify_ipa,
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        sys.exit(2)
    try:
        COMMANDS[sys.argv[1]](sys.argv[2:])
    except RuntimeError as error:
        fail(str(error))
