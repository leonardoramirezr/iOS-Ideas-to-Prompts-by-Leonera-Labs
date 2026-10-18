#!/usr/bin/env python3
"""Genera el contenido de GitHub Pages para instalar los builds (solo stdlib).

  pages.py build-folder --dir DIR --ipa IPA --base-url URL --tag TAG --channel stable|branch
                        --version V --build N --bundle-id ID --title T --branch B --sha SHA
                        [--devices N] [--run-url URL] [--repo OWNER/REPO]
      Copia el IPA y escribe manifest.plist, index.html y build.json en DIR (que ya debe
      tener icon-57.png e icon-512.png).

  pages.py site --root DIR --base-url URL --title T [--keep-branch-builds 20]
      Borra los builds de ramas más antiguos y escribe la portada index.html.
"""

import argparse
import datetime
import html
import json
import os
import plistlib
import shutil
import sys
import urllib.parse

IPA_NAME = "IdeasToPrompts.ipa"

STYLE = """
:root { color-scheme: light dark; --bg: #f2f2f7; --card: #ffffff; --text: #1c1c1e; --muted: #6c6c70;
        --accent: #7a55f5; --line: rgba(60, 60, 67, .18); }
@media (prefers-color-scheme: dark) {
  :root { --bg: #000000; --card: #1c1c1e; --text: #f2f2f7; --muted: #98989f; --accent: #9d82ff; --line: rgba(84, 84, 88, .6); }
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--text);
       font: 17px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
main { max-width: 600px; margin: 0 auto; padding: 32px 16px 56px; }
a { color: var(--accent); }
h1 { margin: 0; font-size: 22px; }
h2 { font-size: 20px; margin: 36px 0 12px; }
.app { display: flex; gap: 16px; align-items: center; }
.app img { width: 76px; height: 76px; border-radius: 18px; flex: none; }
.muted { color: var(--muted); font-size: 14px; }
.button { display: block; text-align: center; background: var(--accent); color: #fff; text-decoration: none;
          font-weight: 600; padding: 15px 18px; border-radius: 14px; margin: 24px 0 10px; }
.button.small { display: inline-block; margin: 0; padding: 7px 14px; border-radius: 10px; font-size: 15px; }
.card { background: var(--card); border-radius: 16px; padding: 0 16px; }
.row { display: flex; justify-content: space-between; align-items: center; gap: 12px; padding: 12px 0;
       border-bottom: 1px solid var(--line); }
.row:last-child { border-bottom: none; }
.row > span:last-child { text-align: right; overflow-wrap: anywhere; }
.badge { display: inline-block; font-size: 12px; font-weight: 600; padding: 2px 8px; border-radius: 999px;
         background: var(--line); color: var(--muted); margin-left: 6px; vertical-align: 2px; }
.badge.stable { background: #34c75933; color: #248a3d; }
"""


def page(title, body):
    return (
        "<!doctype html>\n<html lang=\"es\">\n<head>\n<meta charset=\"utf-8\">\n"
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        f"<title>{html.escape(title)}</title>\n<style>{STYLE}</style>\n</head>\n"
        f"<body>\n<main>\n{body}\n</main>\n</body>\n</html>\n"
    )


def install_url(manifest_url):
    return "itms-services://?action=download-manifest&url=" + urllib.parse.quote(manifest_url, safe="")


def esc(value):
    return html.escape(str(value))


def build_folder(args):
    folder = args.dir
    os.makedirs(folder, exist_ok=True)
    for icon in ("icon-57.png", "icon-512.png"):
        if not os.path.exists(os.path.join(folder, icon)):
            sys.exit(f"Falta {icon} en {folder}")
    shutil.copyfile(args.ipa, os.path.join(folder, IPA_NAME))

    base = args.base_url.rstrip("/") + "/"
    folder_url = base + urllib.parse.quote(args.tag) + "/"
    manifest_url = folder_url + "manifest.plist"
    install = install_url(manifest_url)

    manifest = {
        "items": [{
            "assets": [
                {"kind": "software-package", "url": folder_url + IPA_NAME},
                {"kind": "display-image", "url": folder_url + "icon-57.png"},
                {"kind": "full-size-image", "url": folder_url + "icon-512.png"},
            ],
            "metadata": {
                "bundle-identifier": args.bundle_id,
                "bundle-version": args.version,
                "kind": "software",
                "title": args.title,
            },
        }]
    }
    with open(os.path.join(folder, "manifest.plist"), "wb") as handle:
        plistlib.dump(manifest, handle)

    info = {
        "tag": args.tag,
        "channel": args.channel,
        "version": args.version,
        "build": args.build,
        "branch": args.branch,
        "sha": args.sha,
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "bundle_id": args.bundle_id,
        "title": args.title,
        "ipa": IPA_NAME,
        "devices": args.devices,
        "page_url": folder_url,
        "manifest_url": manifest_url,
        "install_url": install,
        "run_url": args.run_url,
        "repo": args.repo,
    }
    with open(os.path.join(folder, "build.json"), "w") as handle:
        json.dump(info, handle, indent=2, ensure_ascii=False)

    with open(os.path.join(folder, "index.html"), "w") as handle:
        handle.write(build_page(info))

    output = os.environ.get("GITHUB_OUTPUT")
    if output:
        with open(output, "a") as handle:
            handle.write(f"page_url={folder_url}\ninstall_url={install}\n")
    print(f"Página del build: {folder_url}")
    print(f"Enlace de instalación: {install}")


def commit_link(info):
    sha = info.get("sha", "")
    if info.get("repo") and sha:
        return f'<a href="https://github.com/{esc(info["repo"])}/commit/{esc(sha)}">{esc(sha[:7])}</a>'
    return esc(sha[:7])


def build_page(info):
    channel = "Estable" if info["channel"] == "stable" else f"Rama {esc(info['branch'])}"
    rows = [
        ("Versión", f"{esc(info['version'])} ({esc(info['build'])})"),
        ("Canal", channel),
        ("Commit", commit_link(info)),
        ("Fecha", esc(info["date"].replace("T", " ").replace("Z", " UTC"))),
        ("Dispositivos en el perfil", esc(info["devices"]) if info.get("devices") is not None else "—"),
        ("IPA", f'<a href="{IPA_NAME}">Descargar</a>'),
    ]
    if info.get("run_url"):
        rows.append(("Ejecución", f'<a href="{esc(info["run_url"])}">Ver en GitHub Actions</a>'))
    table = "\n".join(f'<div class="row"><span>{label}</span><span>{value}</span></div>' for label, value in rows)
    body = f"""
<div class="app"><img src="icon-512.png" alt="">
<div><h1>{esc(info['title'])}</h1><div class="muted">{esc(info['tag'])}</div></div></div>
<a class="button" href="{esc(info['install_url'])}">Instalar en el iPhone</a>
<p class="muted">Abre esta página en Safari desde un iPhone registrado en el perfil Ad Hoc.
Al terminar, la app aparece en la pantalla de inicio.</p>
<div class="card">
{table}
</div>
<p><a href="../">← Todos los builds</a></p>"""
    return page(f"{info['title']} {info['tag']}", body)


def version_key(version):
    try:
        return tuple(int(part) for part in version.split("."))
    except ValueError:
        return (0,)


def load_builds(root):
    builds = []
    for name in sorted(os.listdir(root)):
        path = os.path.join(root, name, "build.json")
        if os.path.isfile(path):
            with open(path) as handle:
                info = json.load(handle)
            info["folder"] = name
            builds.append(info)
    return builds


def site(args):
    root = args.root
    builds = load_builds(root)
    newest_first = lambda item: (item.get("date", ""), int(item.get("build") or 0))

    branch_builds = sorted((b for b in builds if b.get("channel") != "stable"), key=newest_first, reverse=True)
    for old in branch_builds[args.keep_branch_builds:]:
        shutil.rmtree(os.path.join(root, old["folder"]))
        print(f"Eliminado build antiguo: {old['folder']}")
    removed = {b["folder"] for b in branch_builds[args.keep_branch_builds:]}
    builds = sorted((b for b in builds if b["folder"] not in removed), key=newest_first, reverse=True)

    stable = [b for b in builds if b.get("channel") == "stable"]
    latest = max(stable, key=lambda b: version_key(b.get("version", "0"))) if stable else None
    icon = f"{latest['folder']}/icon-512.png" if latest else (f"{builds[0]['folder']}/icon-512.png" if builds else "")

    if latest:
        hero = (f'<a class="button" href="{esc(latest["install_url"])}">Instalar la última versión estable '
                f'({esc(latest["version"])})</a>\n<p class="muted">Abre esta página en Safari desde un iPhone registrado. '
                f'<a href="{esc(latest["folder"])}/">Detalles de {esc(latest["tag"])}</a></p>')
    else:
        hero = '<p class="muted">Todavía no hay una versión estable: se publica al hacer push a <code>main</code>.</p>'

    rows = []
    for build in builds:
        badge = '<span class="badge stable">Estable</span>' if build.get("channel") == "stable" else \
            f'<span class="badge">{esc(build.get("branch", ""))}</span>'
        date = esc(build.get("date", "").replace("T", " ").replace("Z", " UTC"))
        rows.append(
            f'<div class="row"><span><a href="{esc(build["folder"])}/">{esc(build["tag"])}</a>{badge}'
            f'<br><span class="muted">{esc(build.get("version", ""))} · {date}</span></span>'
            f'<span><a class="button small" href="{esc(build["install_url"])}">Instalar</a></span></div>'
        )
    listing = "\n".join(rows) or '<div class="row"><span class="muted">Aún no hay builds.</span></div>'
    icon_tag = f'<img src="{esc(icon)}" alt="">' if icon else ""

    body = f"""
<div class="app">{icon_tag}
<div><h1>{esc(args.title)}</h1><div class="muted">Builds Ad Hoc</div></div></div>
{hero}
<h2>Todos los builds</h2>
<div class="card">
{listing}
</div>"""
    with open(os.path.join(root, "index.html"), "w") as handle:
        handle.write(page(args.title, body))
    open(os.path.join(root, ".nojekyll"), "w").close()
    print(f"Portada generada con {len(builds)} builds ({len(stable)} estables).")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    folder = commands.add_parser("build-folder")
    folder.add_argument("--dir", required=True)
    folder.add_argument("--ipa", required=True)
    folder.add_argument("--base-url", required=True)
    folder.add_argument("--tag", required=True)
    folder.add_argument("--channel", choices=["stable", "branch"], required=True)
    folder.add_argument("--version", required=True)
    folder.add_argument("--build", required=True)
    folder.add_argument("--bundle-id", required=True)
    folder.add_argument("--title", required=True)
    folder.add_argument("--branch", required=True)
    folder.add_argument("--sha", required=True)
    folder.add_argument("--devices", type=int)
    folder.add_argument("--run-url", default="")
    folder.add_argument("--repo", default="")

    index = commands.add_parser("site")
    index.add_argument("--root", required=True)
    index.add_argument("--base-url", required=True)
    index.add_argument("--title", required=True)
    index.add_argument("--keep-branch-builds", type=int, default=20)

    args = parser.parse_args()
    if args.command == "build-folder":
        build_folder(args)
    else:
        site(args)


if __name__ == "__main__":
    main()
